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

    static func hasEditableFocus() -> Bool {
        guard isAccessibilityTrusted(prompt: false) else {
            // Without Accessibility we cannot detect focus; treat as editable so paste is still attempted.
            return true
        }

        let system = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedStatus == .success, let focused = focusedObject else {
            return false
        }

        let element = focused as! AXUIElement

        if boolAttribute(element, kAXFocusedAttribute as CFString) == false {
            return false
        }

        if let role = stringAttribute(element, kAXRoleAttribute as CFString) {
            let editableRoles: Set<String> = [
                kAXTextFieldRole as String,
                kAXTextAreaRole as String,
                kAXComboBoxRole as String,
                "AXSearchField"
            ]
            if editableRoles.contains(role) {
                return true
            }
        }

        if boolAttribute(element, "AXIsEditable" as CFString) == true {
            return true
        }

        if let attrs = attributeNames(element),
           attrs.contains(kAXValueAttribute as String),
           attrs.contains(kAXSelectedTextAttribute as String)
            || attrs.contains(kAXSelectedTextRangeAttribute as String) {
            // Common pattern for text-like controls and many web fields.
            if let role = stringAttribute(element, kAXRoleAttribute as CFString),
               role == kAXGroupRole as String || role == "AXWebArea" {
                return true
            }
            if stringAttribute(element, kAXRoleAttribute as CFString) == "AXTextField"
                || stringAttribute(element, kAXRoleAttribute as CFString) == "AXTextArea" {
                return true
            }
        }

        // Chromium / Electron contenteditable often reports AXWebArea or AXGroup with settable value.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }

        return false
    }

    /// Copies text and synthesizes ⌘V into the frontmost app.
    static func paste(_ text: String) {
        _ = requestPostEventAccess()
        copyToClipboard(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
