import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    /// `nil` means modifiers-only (hold the modifiers to activate).
    var keyCode: UInt16?
    var modifiers: UInt

    /// Fn + Control — hold to dictate.
    static let defaultDictationShortcut = KeyboardShortcut(
        keyCode: nil,
        modifiers: NSEvent.ModifierFlags([.function, .control]).rawValue
    )

    /// Fn + Control + C — hold to compose an email.
    static let defaultComposeShortcut = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_C),
        modifiers: NSEvent.ModifierFlags([.function, .control]).rawValue
    )

    /// Legacy alias used by older stored settings.
    static let defaultShortcut = defaultDictationShortcut

    init(keyCode: UInt16?, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = Self.normalize(modifiers)
    }

    init(event: NSEvent) {
        let flags = Self.normalizeFlags(event.modifierFlags)
        // If only modifiers are held (or key is a pure modifier), store as modifiers-only.
        if Self.isModifierKeyCode(event.keyCode) {
            self.keyCode = nil
            self.modifiers = flags.rawValue
        } else {
            self.keyCode = event.keyCode
            self.modifiers = flags.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        modifiers = Self.normalize(try container.decode(UInt.self, forKey: .modifiers))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        keycapLabels.joined(separator: "")
    }

    /// Labels for individual keycap chips in the UI.
    var keycapLabels: [String] {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.function) { parts.append("Fn") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if let keyCode {
            parts.append(Self.keyName(for: keyCode))
        }
        return parts
    }

    func matches(event: NSEvent) -> Bool {
        let eventFlags = Self.normalizeFlags(event.modifierFlags)
        guard eventFlags == modifierFlags else { return false }
        if let keyCode {
            return event.keyCode == keyCode
        }
        return Self.isModifierKeyCode(event.keyCode) || event.type == .flagsChanged
    }

    static func normalizeFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift, .function])
    }

    private static func normalize(_ raw: UInt) -> UInt {
        normalizeFlags(NSEvent.ModifierFlags(rawValue: raw)).rawValue
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Shift, kVK_RightShift,
             kVK_Function:
            return true
        default:
            return false
        }
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Function: return "Fn"
        default: return "Key\(keyCode)"
        }
    }
}
