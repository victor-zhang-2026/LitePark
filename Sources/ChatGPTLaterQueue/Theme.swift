import AppKit
import SwiftUI

enum AppearanceMode: String {
    case light
    case dark

    var colorScheme: ColorScheme { self == .light ? .light : .dark }
    var nativeAppearance: NSAppearance? { NSAppearance(named: self == .light ? .aqua : .darkAqua) }
    var symbolName: String { self == .light ? "sun.max" : "moon" }
    var toggleLabel: String { self == .light ? "Switch to Dark Mode" : "Switch to Light Mode" }
}

extension Color {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let laterAccent = Color(nsColor: BrandArtwork.primary)
    static let laterSurface = adaptive(
        light: NSColor(calibratedWhite: 0.97, alpha: 1),
        dark: NSColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1))
    static let laterElevated = adaptive(
        light: .white,
        dark: NSColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1))
    static let laterInk = adaptive(light: NSColor(calibratedWhite: 0.12, alpha: 1), dark: .white)
    static let laterSeparator = laterInk.opacity(0.14)
}
