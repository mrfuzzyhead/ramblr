import AppKit
import ApplicationServices
import Foundation

enum HotKeyAction: Equatable {
    case dictation
    case dictateAndSend
}

/// Global hold-to-talk hotkeys via CGEvent tap.
/// Requires Input Monitoring when other apps are focused.
final class HotKeyManager {
    var onBegin: ((HotKeyAction) -> Void)?
    var onEnd: ((HotKeyAction) -> Void)?
    var onSwitch: ((HotKeyAction) -> Void)?

    private var dictationShortcut: KeyboardShortcut
    private var dictateAndSendShortcut: KeyboardShortcut
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var activeAction: HotKeyAction?
    private var dictationModifiersDown = false
    private var dictateAndSendKeyDown = false
    /// Cached so the event-tap callback can fast-path ⌘ chords without locking.
    fileprivate var shortcutsUseCommand = false
    private let lock = NSLock()

    init(dictation: KeyboardShortcut, dictateAndSend: KeyboardShortcut) {
        self.dictationShortcut = dictation
        self.dictateAndSendShortcut = dictateAndSend
        self.shortcutsUseCommand =
            dictation.modifierFlags.contains(.command)
            || dictateAndSend.modifierFlags.contains(.command)
    }

    deinit {
        stop()
    }

    func update(dictation: KeyboardShortcut, dictateAndSend: KeyboardShortcut) {
        lock.lock()
        dictationShortcut = dictation
        dictateAndSendShortcut = dictateAndSend
        shortcutsUseCommand =
            dictation.modifierFlags.contains(.command)
            || dictateAndSend.modifierFlags.contains(.command)
        activeAction = nil
        dictationModifiersDown = false
        dictateAndSendKeyDown = false
        lock.unlock()
    }

    func start() {
        stop()
        _ = CGRequestListenEventAccess()
        installTap()
        installLocalMonitor()
        startPermissionPolling()
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        lock.lock()
        activeAction = nil
        dictationModifiersDown = false
        dictateAndSendKeyDown = false
        lock.unlock()
    }

    var isTapActive: Bool { eventTap != nil }

    static func hasInputMonitoringAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func requestInputMonitoringAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.eventTap == nil, Self.hasInputMonitoringAccess() {
                self.installTap()
            } else if let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let consumed = self.handle(
                keyCode: event.keyCode,
                flags: event.modifierFlags,
                type: event.type,
                isRepeat: event.isARepeat
            )
            return consumed ? nil : event
        }
    }

    private func installTap() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        // Session tap is enough for shortcuts and is less invasive than HID head-insert,
        // which can disrupt system chords like ⌘Tab when the tap is busy/disabled.
        let tap =
            CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotKeyEventTapCallback,
                userInfo: userInfo
            )
            ?? CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotKeyEventTapCallback,
                userInfo: userInfo
            )
        guard let tap else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns true when the event should be swallowed so the shortcut character is not typed.
    @discardableResult
    fileprivate func handle(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        type: NSEvent.EventType,
        isRepeat: Bool
    ) -> Bool {
        lock.lock()
        let dictation = dictationShortcut
        let dictateAndSend = dictateAndSendShortcut
        defer { lock.unlock() }

        let normalizedFlags = KeyboardShortcut.normalizeFlags(flags)

        switch type {
        case .keyDown:
            if let sendKey = dictateAndSend.keyCode, keyCode == sendKey {
                let modsMatch = normalizedFlags == dictateAndSend.modifierFlags
                if modsMatch {
                    if isRepeat {
                        return true
                    }
                    dictateAndSendKeyDown = true
                    if activeAction == .dictation {
                        activeAction = .dictateAndSend
                        DispatchQueue.main.async { [weak self] in
                            self?.onSwitch?(.dictateAndSend)
                        }
                    } else if activeAction == nil {
                        // Prefer dictate-and-send when its modifiers are a superset match of dictation.
                        if dictation.keyCode == nil,
                           dictation.modifierFlags.isSubset(of: dictateAndSend.modifierFlags),
                           normalizedFlags == dictation.modifierFlags
                            || normalizedFlags == dictateAndSend.modifierFlags {
                            dictationModifiersDown = true
                        }
                        activeAction = .dictateAndSend
                        DispatchQueue.main.async { [weak self] in
                            self?.onBegin?(.dictateAndSend)
                        }
                    }
                    return true
                }
            }

            if let dictationKey = dictation.keyCode, keyCode == dictationKey {
                if activeAction != nil && keyCode == dictationKey {
                    return true
                }
                let matches = normalizedFlags == dictation.modifierFlags
                guard matches else { return false }
                if isRepeat { return true }
                activeAction = .dictation
                DispatchQueue.main.async { [weak self] in
                    self?.onBegin?(.dictation)
                }
                return true
            }

            return false

        case .keyUp:
            if let sendKey = dictateAndSend.keyCode, keyCode == sendKey, dictateAndSendKeyDown {
                dictateAndSendKeyDown = false
                if activeAction == .dictateAndSend {
                    activeAction = nil
                    dictationModifiersDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onEnd?(.dictateAndSend)
                    }
                    return true
                }
            }

            if let dictationKey = dictation.keyCode, keyCode == dictationKey, activeAction == .dictation {
                activeAction = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onEnd?(.dictation)
                }
                return true
            }

            return false

        case .flagsChanged:
            // Modifier-only dictation (e.g. Fn+Ctrl).
            if dictation.keyCode == nil {
                let matches = normalizedFlags == dictation.modifierFlags
                if matches && !dictationModifiersDown && activeAction == nil && !dictateAndSendKeyDown {
                    dictationModifiersDown = true
                    activeAction = .dictation
                    DispatchQueue.main.async { [weak self] in
                        self?.onBegin?(.dictation)
                    }
                } else if dictationModifiersDown || activeAction != nil {
                    let stillHeld: Bool
                    if activeAction == .dictateAndSend, let sendKey = dictateAndSend.keyCode {
                        // Dictate-and-send ends via keyUp on its key, but modifiers releasing also ends it.
                        stillHeld = dictation.modifierFlags.isSubset(of: normalizedFlags)
                            || dictateAndSend.modifierFlags.isSubset(of: normalizedFlags)
                        _ = sendKey
                    } else {
                        stillHeld = matches
                    }

                    if !stillHeld && activeAction != nil {
                        let ending = activeAction ?? .dictation
                        activeAction = nil
                        dictationModifiersDown = false
                        dictateAndSendKeyDown = false
                        DispatchQueue.main.async { [weak self] in
                            self?.onEnd?(ending)
                        }
                    } else if !matches {
                        dictationModifiersDown = false
                    }
                }
            } else if let action = activeAction {
                let required = (action == .dictateAndSend ? dictateAndSend : dictation).modifierFlags
                if !required.isEmpty && required.intersection(normalizedFlags) != required {
                    activeAction = nil
                    dictateAndSendKeyDown = false
                    dictationModifiersDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onEnd?(action)
                    }
                }
            }
            return false

        default:
            return false
        }
    }
}

private func hotKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // Fast-path system ⌘ chords (⌘Tab, ⌘`, etc.) when our shortcuts don't use ⌘.
    // Avoids work that can delay/drop App Switcher events.
    if event.flags.contains(.maskCommand), !manager.shortcutsUseCommand {
        return Unmanaged.passUnretained(event)
    }

    let eventType: NSEvent.EventType
    switch type {
    case .keyDown: eventType = .keyDown
    case .keyUp: eventType = .keyUp
    case .flagsChanged: eventType = .flagsChanged
    default:
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

    let consumed = manager.handle(
        keyCode: keyCode,
        flags: flags,
        type: eventType,
        isRepeat: isRepeat
    )
    return consumed ? nil : Unmanaged.passUnretained(event)
}
