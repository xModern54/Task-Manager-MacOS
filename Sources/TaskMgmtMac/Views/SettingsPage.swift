import SwiftUI

struct SettingsPage: View {
    @State private var refreshInterval = SettingsRefreshInterval.half
    @State private var selectedTheme = SettingsTheme.system
    @State private var accentFollowsSystem = true
    @State private var customAccentColor = SettingsAccentColor.blue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .taskManagerFont(16, weight: .semibold)
                    .padding(.leading, 22)

                Spacer()
            }
            .frame(height: 61)
            .background(WindowsTaskManagerTheme.content)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WindowsTaskManagerTheme.separator)
                    .frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsSection(title: "General") {
                        SettingsValueRow(label: "Role", value: RootLaunchManager.isRunningAsRoot ? "Root" : "User")
                        SettingsMenuRow(
                            label: "Refresh interval",
                            value: $refreshInterval,
                            options: SettingsRefreshInterval.allCases
                        )
                    }

                    SettingsSection(title: "Appearance") {
                        SettingsPickerRow(label: "Theme", selection: $selectedTheme)
                        SettingsToggleRow(label: "Use macOS accent color", value: $accentFollowsSystem)
                        SettingsAccentColorRow(
                            label: "Custom accent color",
                            selection: $customAccentColor,
                            isEnabled: !accentFollowsSystem
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(WindowsTaskManagerTheme.table)
        }
        .background(WindowsTaskManagerTheme.content)
    }
}

private enum SettingsTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: Self { self }
}

private enum SettingsRefreshInterval: Double, CaseIterable, Identifiable {
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
}

private enum SettingsAccentColor: String, CaseIterable, Identifiable {
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

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .taskManagerFont(13, weight: .semibold)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(WindowsTaskManagerTheme.content)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WindowsTaskManagerTheme.separator, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            Text(value)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
    }
}

private struct SettingsToggleRow: View {
    let label: String
    @Binding var value: Bool
    var secondaryText: String?

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            if let secondaryText {
                Text(secondaryText)
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            }

            Toggle("", isOn: $value)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsMenuRow<Option: Identifiable & Hashable>: View where Option.ID == Option {
    let label: String
    @Binding var value: Option
    let options: [Option]

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            Picker("", selection: $value) {
                ForEach(options) { option in
                    Text(title(for: option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 155, alignment: .trailing)
        }
    }

    private func title(for option: Option) -> String {
        if let refreshInterval = option as? SettingsRefreshInterval {
            return refreshInterval.title
        }

        return String(describing: option)
    }
}

private struct SettingsPickerRow: View {
    let label: String
    @Binding var selection: SettingsTheme

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(SettingsTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
    }
}

private struct SettingsAccentColorRow: View {
    let label: String
    @Binding var selection: SettingsAccentColor
    let isEnabled: Bool

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            HStack(spacing: 8) {
                ForEach(SettingsAccentColor.allCases) { accentColor in
                    Button {
                        guard isEnabled else { return }
                        selection = accentColor
                    } label: {
                        Circle()
                            .fill(accentColor.color)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if selection == accentColor {
                                    Circle()
                                        .stroke(WindowsTaskManagerTheme.textPrimary, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .help(accentColor.rawValue)
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
        }
    }
}

private struct SettingsRowContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
                .padding(.leading, 14)
        }
        .contentShape(Rectangle())
    }
}
