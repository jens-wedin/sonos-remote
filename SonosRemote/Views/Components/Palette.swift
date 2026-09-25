import SwiftUI

/// App text and surface tokens verified against WCAG 1.4.3 in light and dark appearance.
/// `.secondary` (≈3.9:1 on white) and `.tertiary` (≈1.9:1) are never used for text the user must read.
enum Palette {
    static let disabledOpacity = 0.55

    static func border(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.55 : 0.45)
    }
}

extension Color {
    /// Supporting text: labels, second lines, captions. Primary at 72% ≈ 5.2:1 on white, ≈ 7:1 on black.
    static let supporting = Color.primary.opacity(0.72)
    /// The faintest readable tier (album line, footer). Primary at 60% ≈ 4.6:1 on white.
    static let faint = Color.primary.opacity(0.60)
    /// Link text (the update card's actions) that clears 4.5:1 on both grounds: ≈ 6.2:1 on white, ≈ 8.8:1 on black.
    static let link = Color(light: Color(red: 0.0, green: 0.36, blue: 0.80), dark: Color(red: 0.45, green: 0.66, blue: 1.0))
    /// Error text that clears 4.5:1 on both grounds.
    static let errorText = Color(light: Color(red: 0.72, green: 0.13, blue: 0.11), dark: Color(red: 1.0, green: 0.56, blue: 0.51))

    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}
