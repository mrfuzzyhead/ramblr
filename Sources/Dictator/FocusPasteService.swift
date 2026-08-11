import AppKit
import ApplicationServices
import Foundation

/// Snapshot of the general pasteboard so dictation can restore prior contents after paste.
struct ClipboardSnapshot {
    fileprivate let items: [[NSPasteboard.PasteboardType: Data]]
}

enum FocusPasteService {
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// Needed to synthesize ⌘V into other apps.
    static func hasPostEventAccess() -> Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns whether we should attempt to paste into the frontmost app.
    ///
    /// Chromium/Electron often return no focused AX element even when a caret is
    /// active. In that case we optimistically paste (text is already on the clipboard).
    static func hasEditableFocus() -> Bool {
        guard isAccessibilityTrusted(prompt: false) else {
            // Without Accessibility we cannot detect focus; treat as editable so paste is still attempted.
            return true
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        // Don't paste into Ramblr itself unless a genuine text field is focused.
        let isSelf = frontApp.bundleIdentifier == Bundle.main.bundleIdentifier
            || frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier

        enableChromiumAccessibilityIfNeeded(for: frontApp)

        guard let focused = copyFocusedElement() else {
            // Nil focus is common for Chrome/Electron web fields — attempt paste
            // unless Ramblr is frontmost.
            return !isSelf
        }

        if isEditableElement(focused) {
            return true
        }

        // Walk ancestors; browsers often focus a child/container around the field.
        var current: AXUIElement? = focused
        for _ in 0..<6 {
            guard let element = current, let parent = copyParent(element) else { break }
            if isEditableElement(parent) {
                return true
            }
            current = parent
        }

        if let role = stringAttribute(focused, kAXRoleAttribute as CFString),
           Self.nonEditableRoles.contains(role) {
            return false
        }

        // Ambiguous role with a focused element in another app — attempt paste.
        return !isSelf
    }

    /// Copies text and synthesizes ⌘V into the frontmost app.
    /// When `snapshot` is provided, prior clipboard contents are restored after paste.
    static func paste(_ text: String, restoringClipboard snapshot: ClipboardSnapshot? = nil) {
        _ = requestPostEventAccess()
        copyToClipboard(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
            restoreClipboardAfterPaste(snapshot)
        }
    }

    /// Pastes text, then presses Return/Enter to send.
    /// When `snapshot` is provided, prior clipboard contents are restored after paste and Return.
    static func pasteAndSend(_ text: String, restoringClipboard snapshot: ClipboardSnapshot? = nil) {
        _ = requestPostEventAccess()
        copyToClipboard(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                synthesizeReturn()
                restoreClipboardAfterPaste(snapshot)
            }
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Captures current general-pasteboard contents (all available typed data).
    static func captureClipboard() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var typedData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typedData[type] = data
                }
            }
            if !typedData.isEmpty {
                items.append(typedData)
            }
        }
        return ClipboardSnapshot(items: items)
    }

    static func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let pasteboardItems: [NSPasteboardItem] = snapshot.items.map { typedData in
            let item = NSPasteboardItem()
            for (type, data) in typedData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    /// Gives the target app a moment to read the pasteboard before we put the old contents back.
    private static func restoreClipboardAfterPaste(_ snapshot: ClipboardSnapshot?) {
        guard let snapshot else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            restoreClipboard(snapshot)
        }
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea",
        "AXTextEntry",
        "AXDocument",
    ]

    private static let nonEditableRoles: Set<String> = [
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXStaticTextRole as String,
        kAXImageRole as String,
        kAXMenuItemRole as String,
        "AXTab",
        "AXToolbar",
        "AXLink",
        "AXHeading",
        "AXValueIndicator",
        "AXSlider",
        "AXProgressIndicator",
    ]

    private static func copyFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedStatus == .success, let focused = focusedObject else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private static func isEditableElement(_ element: AXUIElement) -> Bool {
        if let role = stringAttribute(element, kAXRoleAttribute as CFString),
           editableRoles.contains(role) {
            return true
        }

        if let subrole = stringAttribute(element, kAXSubroleAttribute as CFString),
           subrole == "AXSearchField"
            || subrole == "AXTextFieldEntry"
            || subrole == "AXSecureTextField" {
            return true
        }

        if boolAttribute(element, "AXIsEditable" as CFString) == true
            || boolAttribute(element, "AXEditable" as CFString) == true {
            return true
        }

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }

        if let attrs = attributeNames(element),
           attrs.contains(kAXSelectedTextAttribute as String)
            || attrs.contains(kAXSelectedTextRangeAttribute as String)
            || attrs.contains(kAXInsertionPointLineNumberAttribute as String) {
            if let role = stringAttribute(element, kAXRoleAttribute as CFString),
               Self.nonEditableRoles.contains(role) {
                return false
            }
            return true
        }

        return false
    }

    /// Chrome/Electron lazily build their AX tree until an assistive client opts in.
    /// Only set the narrow Chromium flag — `AXEnhancedUserInterface` can disrupt
    /// focus/keyboard behavior when switching back to that app with ⌘Tab.
    private static func enableChromiumAccessibilityIfNeeded(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let trueValue = kCFBooleanTrue as CFTypeRef

        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            trueValue
        )
    }

    private static func copyParent(_ element: AXUIElement) -> AXUIElement? {
        var parentObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentObject
        ) == .success,
            let parent = parentObject
        else {
            return nil
        }
        return (parent as! AXUIElement)
    }

    /// Posts V with the Command flag only — never Command keyDown/Up.
    /// `privateState` + HID tap delivers paste without sticky ⌘ for App Switcher.
    private static func synthesizePaste() {
        guard let source = CGEventSource(stateID: .privateState) else { return }

        // kVK_ANSI_V = 0x09
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand

        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
    }

    private static func synthesizeReturn() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        // kVK_Return
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String
        else {
            return nil
        }
        return string
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func attributeNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let array = names as? [String]
        else {
            return nil
        }
        return array
    }
}
