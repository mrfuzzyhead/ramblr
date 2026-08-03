import AppKit
import ApplicationServices
import Foundation

/// Global hold-to-talk hotkey via CGEvent tap.
/// Requires Input Monitoring when other apps are focused.
final class HotKeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var shortcut: KeyboardShortcut
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var isShortcutDown = false
    private let lock = NSLock()

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
    }

    deinit {
        stop()
    }

    func update(shortcut: KeyboardShortcut) {
        lock.lock()
        self.shortcut = shortcut
        isShortcutDown = false
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
        isShortcutDown = false
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

        // Prefer HID-level tap so held-key repeats are intercepted before AppKit
        // can play the system "invalid key" beep. Fall back to session tap.
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
        let currentShortcut = shortcut
        defer { lock.unlock() }

        let normalizedFlags = KeyboardShortcut.normalizeFlags(flags)

        switch type {
        case .keyDown:
            // While the shortcut is held, always swallow that key — including
            // autorepeat. Repeat events sometimes arrive with stripped modifier
            // flags; if they leak through, macOS plays the warning beep on each
            // repeat (especially for combos like ⌘⇧D that map to menu items).
            if isShortcutDown && keyCode == currentShortcut.keyCode {
                return true
            }

            let matches = keyCode == currentShortcut.keyCode
                && normalizedFlags == currentShortcut.modifierFlags
            guard matches else { return false }

            // Matching orphan repeats: swallow so they cannot beep, but do not
            // start a new hold session without a real initial keyDown.
            if isRepeat {
                return true
            }

            isShortcutDown = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
            return true

        case .keyUp:
            guard keyCode == currentShortcut.keyCode else { return false }
            guard isShortcutDown else { return false }
            isShortcutDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
            return true

        case .flagsChanged:
            guard isShortcutDown else { return false }
            let required = currentShortcut.modifierFlags
            if !required.isEmpty && required.intersection(normalizedFlags) != required {
                isShortcutDown = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return false

        default:
            return false
        }
    }
}

extension KeyboardShortcut {
    static func normalizeFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
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
