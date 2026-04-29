import SwiftUI

struct StartupAppsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            StartupAppsCommandBar()

            StartupAppsTable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(WindowsTaskManagerTheme.content)
    }
}

private struct StartupAppsCommandBar: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Startup apps")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 22)

            Spacer()

            StartupCommandButton(icon: "checkmark", title: "Enable", isEnabled: false)
            StartupCommandButton(icon: "nosign", title: "Disable", isEnabled: false)
            StartupCommandButton(icon: "info.rectangle", title: "Properties", isEnabled: false)

            Image(systemName: "ellipsis")
                .taskManagerFont(18, weight: .bold)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: 48, height: 50)
        }
        .frame(height: 61)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct StartupCommandButton: View {
    let icon: String
    let title: String
    let isEnabled: Bool

    var body: some View {
        Button {} label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .taskManagerFont(15)

                Text(title)
                    .taskManagerFont(13)
            }
            .frame(height: 50)
            .padding(.horizontal, 10)
            .foregroundStyle(isEnabled ? WindowsTaskManagerTheme.textPrimary : WindowsTaskManagerTheme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct StartupAppsTable: View {
    var body: some View {
        VStack(spacing: 0) {
            StartupAppsTableHeader()

            VStack(spacing: 10) {
                Image(systemName: "speedometer")
                    .taskManagerFont(28)
                    .foregroundStyle(WindowsTaskManagerTheme.textMuted)

                Text("No startup items loaded yet")
                    .taskManagerFont(15, weight: .semibold)

                Text("Launch agents, daemons, and login items will appear here once the provider is connected.")
                    .taskManagerFont(13)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .background(WindowsTaskManagerTheme.table)
    }
}

private struct StartupAppsTableHeader: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                StartupHeaderCell(title: "Name", width: width * 0.38, isSorted: true)
                StartupHeaderCell(title: "Publisher", width: width * 0.24)
                StartupHeaderCell(title: "Status", width: width * 0.18)
                StartupHeaderCell(title: "Startup impact", width: width * 0.20, showsSeparator: false)
            }
        }
        .frame(height: 58)
        .background(WindowsTaskManagerTheme.table)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct StartupHeaderCell: View {
    let title: String
    let width: CGFloat
    var isSorted = false
    var showsSeparator = true

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            if isSorted {
                Image(systemName: "chevron.up")
                    .taskManagerFont(9, weight: .semibold)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            }
        }
        .padding(.leading, 16)
        .frame(width: width, height: 58, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            if showsSeparator {
                Rectangle()
                    .fill(WindowsTaskManagerTheme.separator)
                    .frame(width: 1, height: 36)
            }
        }
    }
}
