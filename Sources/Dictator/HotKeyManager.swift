import AppKit
import ApplicationServices
import Foundation

enum HotKeyAction: Equatable {
    case dictation
    case compose
}

/// Global hold-to-talk hotkeys via CGEvent tap.
/// Requires Input Monitoring when other apps are focused.
final class HotKeyManager {
    var onBegin: ((HotKeyAction) -> Void)?
    var onEnd: ((HotKeyAction) -> Void)?
    var onSwitch: ((HotKeyAction) -> Void)?

    private var dictationShortcut: KeyboardShortcut
    private var composeShortcut: KeyboardShortcut
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var activeAction: HotKeyAction?
    private var dictationModifiersDown = false
    private var composeKeyDown = false
    private let lock = NSLock()

    init(dictation: KeyboardShortcut, compose: KeyboardShortcut) {
        self.dictationShortcut = dictation
        self.composeShortcut = compose
    }

    deinit {
        stop()
    }

    func update(dictation: KeyboardShortcut, compose: KeyboardShortcut) {
        lock.lock()
        dictationShortcut = dictation
        composeShortcut = compose
        activeAction = nil
        dictationModifiersDown = false
        composeKeyDown = false
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
        composeKeyDown = false
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
        let tap =
            CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotKeyEventTapCallback,
                userInfo: userInfo
            )
            ?? CGEvent.tapCreate(
                tap: .cgSessionEventTap,
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
        let compose = composeShortcut
        defer { lock.unlock() }

        let normalizedFlags = KeyboardShortcut.normalizeFlags(flags)

        switch type {
        case .keyDown:
            if let composeKey = compose.keyCode, keyCode == composeKey {
                let modsMatch = normalizedFlags == compose.modifierFlags
                if modsMatch {
                    if isRepeat {
                        return true
                    }
                    composeKeyDown = true
                    if activeAction == .dictation {
                        activeAction = .compose
                        DispatchQueue.main.async { [weak self] in
                            self?.onSwitch?(.compose)
                        }
                    } else if activeAction == nil {
                        // Prefer compose when its modifiers are a superset match of dictation.
                        if dictation.keyCode == nil,
                           dictation.modifierFlags.isSubset(of: compose.modifierFlags),
                           normalizedFlags == dictation.modifierFlags
                            || normalizedFlags == compose.modifierFlags {
                            dictationModifiersDown = true
                        }
                        activeAction = .compose
                        DispatchQueue.main.async { [weak self] in
                            self?.onBegin?(.compose)
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
            if let composeKey = compose.keyCode, keyCode == composeKey, composeKeyDown {
                composeKeyDown = false
                if activeAction == .compose {
                    activeAction = nil
                    dictationModifiersDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onEnd?(.compose)
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
                if matches && !dictationModifiersDown && activeAction == nil && !composeKeyDown {
                    dictationModifiersDown = true
                    activeAction = .dictation
                    DispatchQueue.main.async { [weak self] in
                        self?.onBegin?(.dictation)
                    }
                } else if dictationModifiersDown || activeAction != nil {
                    let stillHeld: Bool
                    if activeAction == .compose, let composeKey = compose.keyCode {
                        // Compose ends via keyUp on its key, but modifiers releasing also ends it.
                        stillHeld = dictation.modifierFlags.isSubset(of: normalizedFlags)
                            || compose.modifierFlags.isSubset(of: normalizedFlags)
                        _ = composeKey
                    } else {
                        stillHeld = matches
                    }

                    if !stillHeld && activeAction != nil {
                        let ending = activeAction ?? .dictation
                        activeAction = nil
                        dictationModifiersDown = false
                        composeKeyDown = false
                        DispatchQueue.main.async { [weak self] in
                            self?.onEnd?(ending)
                        }
                    } else if !matches {
                        dictationModifiersDown = false
                    }
                }
            } else if let action = activeAction {
                let required = (action == .compose ? compose : dictation).modifierFlags
                if !required.isEmpty && required.intersection(normalizedFlags) != required {
                    activeAction = nil
                    composeKeyDown = false
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

    guard let nsEvent = NSEvent(cgEvent: event) else {
        return Unmanaged.passUnretained(event)
    }

    let consumed = manager.handle(
        keyCode: nsEvent.keyCode,
        flags: nsEvent.modifierFlags,
        type: nsEvent.type,
        isRepeat: nsEvent.isARepeat
    )
    return consumed ? nil : Unmanaged.passUnretained(event)
}
