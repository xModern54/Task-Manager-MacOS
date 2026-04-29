@preconcurrency import AppKit
import SwiftUI

struct StartupAppsPage: View {
    @State private var startupItems: [StartupItem] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            StartupAppsCommandBar()

            StartupAppsTable(items: startupItems, isLoading: isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(WindowsTaskManagerTheme.content)
        .task {
            await loadStartupItems()
        }
    }

    private func loadStartupItems() async {
        isLoading = true
        startupItems = await CompositeStartupItemProvider().startupItems()
        isLoading = false
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
    let items: [StartupItem]
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            StartupAppsTableHeader()

            if isLoading {
                StartupAppsLoadingView()
            } else if items.isEmpty {
                StartupAppsEmptyView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            StartupItemRow(item: item)
                        }
                    }
                }
            }
        }
        .background(WindowsTaskManagerTheme.table)
    }
}

private struct StartupAppsLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading startup items")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct StartupAppsEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "speedometer")
                .taskManagerFont(28)
                .foregroundStyle(WindowsTaskManagerTheme.textMuted)

            Text("No startup items found")
                .taskManagerFont(15, weight: .semibold)

            Text("Login items, launch agents, daemons, and background activity items will appear here.")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct StartupItemRow: View {
    let item: StartupItem

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                StartupNameCell(item: item, width: width * 0.38)
                StartupTextCell(text: item.publisher, width: width * 0.24)
                StartupTextCell(text: statusText, width: width * 0.18)
                StartupTextCell(text: item.impact.rawValue, width: width * 0.20, showsSeparator: false)
            }
        }
        .frame(height: 46)
        .background(WindowsTaskManagerTheme.table)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }

    private var statusText: String {
        if item.isHidden {
            return "\(item.status.rawValue), hidden"
        }

        return item.status.rawValue
    }
}

private struct StartupNameCell: View {
    let item: StartupItem
    let width: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            StartupItemIcon(path: item.path)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .taskManagerFont(13)
                    .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                    .lineLimit(1)

                Text(item.detail ?? item.path ?? item.source.rawValue)
                    .taskManagerFont(11)
                    .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.leading, 16)
        .frame(width: width, height: 46, alignment: .leading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(width: 1, height: 30)
        }
    }
}

private struct StartupTextCell: View {
    let text: String
    let width: CGFloat
    var showsSeparator = true

    var body: some View {
        Text(text)
            .taskManagerFont(13)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 16)
            .frame(width: width, height: 46, alignment: .leading)
            .clipped()
            .overlay(alignment: .trailing) {
                if showsSeparator {
                    Rectangle()
                        .fill(WindowsTaskManagerTheme.separator)
                        .frame(width: 1, height: 30)
                }
            }
    }
}

private struct StartupItemIcon: View {
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
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
