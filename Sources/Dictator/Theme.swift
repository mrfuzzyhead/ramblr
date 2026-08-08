import AppKit
import SwiftUI

enum RamblrTheme {
    static let accent = Color(red: 1.0, green: 198.0 / 255.0, blue: 0.0) // #FFC600
    static let accentNS = NSColor(red: 1.0, green: 198.0 / 255.0, blue: 0.0, alpha: 1.0)

    static let background = Color(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 18.0 / 255.0)
    static let sidebar = Color(red: 36.0 / 255.0, green: 36.0 / 255.0, blue: 36.0 / 255.0)
    static let card = Color(red: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0)
    static let elevated = Color(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0)
    static let border = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.4)
    static let selection = Color.white.opacity(0.12)
    static let hudBackground = Color(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0)
    static let levelActive = Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
    static let levelInactive = Color.white.opacity(0.15)
    static let recordingDot = Color(red: 1.0, green: 69.0 / 255.0, blue: 58.0 / 255.0)
    static let completeDot = Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
}
