import SwiftUI

extension Color {
    static var effectiveAccent: Color {
        .accentColor
    }

    static var effectiveAccentForeground: Color {
        Color(nsColor: .effectiveAccentForeground)
    }

    static var effectiveAccentBackground: Color {
        .accentColor.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        .controlAccentColor
    }

    static var effectiveAccentForeground: NSColor {
        .controlAccentColor.blended(withFraction: 0.35, of: .white) ?? .controlAccentColor
    }

    static var effectiveAccentBackground: NSColor {
        .controlAccentColor.withAlphaComponent(0.25)
    }
}
