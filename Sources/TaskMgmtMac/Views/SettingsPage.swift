import SwiftUI

struct SettingsPage: View {
    @State private var launchAsRoot = RootLaunchManager.isRunningAsRoot
    @State private var refreshInterval = 0.5
    @State private var showCompactGraphs = true
    @State private var selectedTheme = SettingsTheme.system
    @State private var accentFollowsSystem = true
    @State private var reduceAnimations = false

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
                        SettingsToggleRow(
                            label: "Launch as root",
                            value: $launchAsRoot,
                            secondaryText: RootLaunchManager.isRunningAsRoot ? "Active" : "Inactive"
                        )
                        SettingsStepperRow(
                            label: "Refresh interval",
                            value: $refreshInterval,
                            range: 0.5...5,
                            step: 0.5,
                            formattedValue: "\(String(format: "%.1f", refreshInterval)) seconds"
                        )
                        SettingsToggleRow(label: "Compact performance graphs", value: $showCompactGraphs)
                    }

                    SettingsSection(title: "Appearance") {
                        SettingsPickerRow(label: "Theme", selection: $selectedTheme)
                        SettingsToggleRow(label: "Use macOS accent color", value: $accentFollowsSystem)
                        SettingsToggleRow(label: "Reduce sidebar animations", value: $reduceAnimations)
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

private struct SettingsStepperRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formattedValue: String

    var body: some View {
        SettingsRowContainer {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            Text(formattedValue)
                .taskManagerFont(12)
                .monospacedDigit()
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: 86, alignment: .trailing)

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
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
