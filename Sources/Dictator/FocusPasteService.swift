import AppKit
import ApplicationServices
import Foundation

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
    static func paste(_ text: String) {
        _ = requestPostEventAccess()
        copyToClipboard(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
        }
    }

    /// Pastes text, then presses Return/Enter to send.
    static func pasteAndSend(_ text: String) {
        _ = requestPostEventAccess()
        copyToClipboard(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                synthesizeReturn()
            }
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
    private static func enableChromiumAccessibilityIfNeeded(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let trueValue = kCFBooleanTrue as CFTypeRef

        // Prefer the narrower Chromium flag; also try Enhanced User Interface.
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            trueValue
        )
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
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

    private static func synthesizePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand

        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
    }

    private static func synthesizeReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
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
