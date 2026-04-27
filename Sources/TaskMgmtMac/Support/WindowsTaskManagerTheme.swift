import AppKit
import SwiftUI

enum WindowsTaskManagerTheme {
    static let windowBackground = adaptive(light: rgb(0.955, 0.965, 0.976), dark: rgb(0.074, 0.082, 0.094))
    static let titleBar = adaptive(light: rgb(0.938, 0.950, 0.965), dark: rgb(0.098, 0.118, 0.153))
    static let sidebar = adaptive(light: rgb(0.925, 0.941, 0.957), dark: rgb(0.086, 0.110, 0.151))
    static let sidebarSelection = adaptive(light: rgb(0.850, 0.884, 0.916), dark: rgb(0.145, 0.169, 0.216))
    static let content = adaptive(light: rgb(0.985, 0.986, 0.988), dark: rgb(0.074, 0.076, 0.073))
    static let table = adaptive(light: rgb(0.992, 0.993, 0.995), dark: rgb(0.078, 0.081, 0.077))
    static let tableSelection = adaptive(light: rgb(0.905, 0.924, 0.946), dark: rgb(0.153, 0.153, 0.145))
    static let separator = adaptive(light: NSColor.black.withAlphaComponent(0.105), dark: NSColor.white.withAlphaComponent(0.075))
    static let textPrimary = adaptive(light: rgb(0.080, 0.087, 0.100), dark: rgb(0.948, 0.954, 0.966))
    static let textSecondary = adaptive(light: rgb(0.350, 0.376, 0.414), dark: rgb(0.730, 0.751, 0.775))
    static let textMuted = adaptive(light: rgb(0.590, 0.615, 0.650), dark: rgb(0.450, 0.462, 0.482))
    static let systemAccent = Color(nsColor: .controlAccentColor)
    static let accent = systemAccent
    static let searchBackground = adaptive(light: NSColor.black.withAlphaComponent(0.070), dark: NSColor.white.withAlphaComponent(0.085))
    static let searchBackgroundFocused = adaptive(light: NSColor.black.withAlphaComponent(0.090), dark: NSColor.white.withAlphaComponent(0.110))
    static let searchBorder = adaptive(light: NSColor.black.withAlphaComponent(0.140), dark: NSColor.white.withAlphaComponent(0.125))
    static let searchBorderFocused = adaptive(light: NSColor.black.withAlphaComponent(0.220), dark: NSColor.white.withAlphaComponent(0.200))
    static let metricHeat = adaptive(light: rgb(0.848, 0.928, 0.995), dark: rgb(0.020, 0.176, 0.331))
    static let metricHeatStrong = adaptive(light: rgb(0.676, 0.855, 0.995), dark: rgb(0.030, 0.296, 0.559))

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
            return bestMatch == .darkAqua ? dark : light
        })
    }
}

extension View {
    func taskManagerFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight, design: .default))
    }
}
