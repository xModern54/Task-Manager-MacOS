import SwiftUI

struct SettingsPage: View {
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

            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "General") {
                    SettingsStaticRow(label: "Run mode", value: RootLaunchManager.isRunningAsRoot ? "Root" : "User")
                    SettingsStaticRow(label: "Refresh interval", value: "0.5 seconds")
                }

                SettingsSection(title: "Appearance") {
                    SettingsStaticRow(label: "Theme", value: "System")
                    SettingsStaticRow(label: "Accent color", value: "macOS")
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WindowsTaskManagerTheme.table)
        }
        .background(WindowsTaskManagerTheme.content)
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
            .background(WindowsTaskManagerTheme.content)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WindowsTaskManagerTheme.separator, lineWidth: 1)
            }
        }
        .frame(width: 420, alignment: .leading)
    }
}

private struct SettingsStaticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .taskManagerFont(13)

            Spacer()

            Text(value)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .frame(height: 38)
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }
}
