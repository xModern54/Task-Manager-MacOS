import SwiftUI

@MainActor
final class TaskManagerSettings: ObservableObject {
    @Published var refreshInterval: SettingsRefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }

    @Published var theme: SettingsTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var useMacOSAccentColor: Bool {
        didSet { defaults.set(useMacOSAccentColor, forKey: Keys.useMacOSAccentColor) }
    }

    @Published var customAccentColor: SettingsAccentColor {
        didSet { defaults.set(customAccentColor.rawValue, forKey: Keys.customAccentColor) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let refreshRawValue = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = SettingsRefreshInterval(rawValue: refreshRawValue) ?? .half

        let themeRawValue = defaults.string(forKey: Keys.theme) ?? SettingsTheme.system.rawValue
        theme = SettingsTheme(rawValue: themeRawValue) ?? .system

        if defaults.object(forKey: Keys.useMacOSAccentColor) == nil {
            useMacOSAccentColor = true
        } else {
            useMacOSAccentColor = defaults.bool(forKey: Keys.useMacOSAccentColor)
        }

        let accentRawValue = defaults.string(forKey: Keys.customAccentColor) ?? SettingsAccentColor.blue.rawValue
        customAccentColor = SettingsAccentColor(rawValue: accentRawValue) ?? .blue
    }

    var preferredColorScheme: ColorScheme? {
        theme.colorScheme
    }

    var effectiveAccentColor: Color {
        useMacOSAccentColor ? WindowsTaskManagerTheme.systemAccent : customAccentColor.color
    }

    private enum Keys {
        static let refreshInterval = "settings.refreshInterval"
        static let theme = "settings.theme"
        static let useMacOSAccentColor = "settings.useMacOSAccentColor"
        static let customAccentColor = "settings.customAccentColor"
    }
}

enum SettingsTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum SettingsRefreshInterval: Double, CaseIterable, Identifiable {
    case eighth = 0.125
    case quarter = 0.25
    case half = 0.5
    case one = 1

    var id: Self { self }

    var title: String {
        switch self {
        case .eighth:
            "0.125 seconds"
        case .quarter:
            "0.25 seconds"
        case .half:
            "0.5 seconds"
        case .one:
            "1 second"
        }
    }

    var duration: Duration {
        .milliseconds(Int((rawValue * 1000).rounded()))
    }
}

enum SettingsAccentColor: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case green = "Green"

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue:
            Color(red: 0.05, green: 0.47, blue: 0.98)
        case .purple:
            Color(red: 0.49, green: 0.28, blue: 0.91)
        case .pink:
            Color(red: 0.90, green: 0.20, blue: 0.55)
        case .red:
            Color(red: 0.93, green: 0.20, blue: 0.22)
        case .orange:
            Color(red: 0.95, green: 0.52, blue: 0.12)
        case .green:
            Color(red: 0.18, green: 0.64, blue: 0.34)
        }
    }
}
