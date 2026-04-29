@preconcurrency import AppKit
import SwiftUI

struct StartupAppsPage: View {
    @State private var startupItems: [StartupItem] = []
    @State private var isLoading = true
    @State private var selectedItemID: StartupItem.ID?
    @State private var propertiesItem: StartupItem?
    @State private var isApplyingAction = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            StartupAppsCommandBar(
                selectedItem: selectedItem,
                isApplyingAction: isApplyingAction,
                onSetEnabled: { enabled in
                    Task {
                        await setSelectedItemEnabled(enabled)
                    }
                },
                onShowProperties: {
                    propertiesItem = selectedItem
                }
            )

            StartupAppsTable(
                items: startupItems,
                isLoading: isLoading,
                selectedItemID: selectedItemID,
                onSelect: { item in
                    selectedItemID = item.id
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(WindowsTaskManagerTheme.content)
        .task {
            await loadStartupItems()
        }
        .sheet(item: $propertiesItem) { item in
            StartupItemPropertiesSheet(item: item)
        }
        .alert("Startup action failed", isPresented: actionErrorBinding) {
            Button("OK") {
                actionErrorMessage = nil
            }
        } message: {
            Text(actionErrorMessage ?? "The selected startup item could not be changed.")
        }
    }

    private func loadStartupItems() async {
        isLoading = true
        startupItems = await CompositeStartupItemProvider().startupItems()
        if let selectedItemID, !startupItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
        isLoading = false
    }

    private var selectedItem: StartupItem? {
        guard let selectedItemID else { return nil }
        return startupItems.first { $0.id == selectedItemID }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private func setSelectedItemEnabled(_ enabled: Bool) async {
        guard let selectedItem, selectedItem.isControllable else { return }

        isApplyingAction = true
        let result = await StartupItemLaunchController().setEnabled(enabled, item: selectedItem)
        isApplyingAction = false

        if result.success {
            await loadStartupItems()
        } else {
            actionErrorMessage = result.message ?? "launchctl returned an error."
        }
    }
}

private struct StartupAppsCommandBar: View {
    let selectedItem: StartupItem?
    let isApplyingAction: Bool
    let onSetEnabled: (Bool) -> Void
    let onShowProperties: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("Startup apps")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 22)

            Spacer()

            StartupCommandButton(icon: "checkmark", title: "Enable", isEnabled: canEnable) {
                onSetEnabled(true)
            }
            StartupCommandButton(icon: "nosign", title: "Disable", isEnabled: canDisable) {
                onSetEnabled(false)
            }
            StartupCommandButton(icon: "info.rectangle", title: "Properties", isEnabled: selectedItem != nil) {
                onShowProperties()
            }

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

    private var canEnable: Bool {
        guard let selectedItem, selectedItem.isControllable, !isApplyingAction else { return false }
        return selectedItem.status != .enabled
    }

    private var canDisable: Bool {
        guard let selectedItem, selectedItem.isControllable, !isApplyingAction else { return false }
        return selectedItem.status != .disabled
    }
}

private struct StartupCommandButton: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    let selectedItemID: StartupItem.ID?
    let onSelect: (StartupItem) -> Void

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
                            StartupItemRow(item: item, isSelected: item.id == selectedItemID)
                                .onTapGesture {
                                    onSelect(item)
                                }
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
    let isSelected: Bool

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
        .background(rowBackground)
        .contentShape(Rectangle())
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

    private var rowBackground: some ShapeStyle {
        isSelected ? WindowsTaskManagerTheme.accent.opacity(0.18) : WindowsTaskManagerTheme.table
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
    var size: CGFloat = 20

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
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct StartupItemPropertiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: StartupItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                StartupItemIcon(path: item.path, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .taskManagerFont(17, weight: .semibold)
                        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                        .lineLimit(1)

                    Text(item.publisher)
                        .taskManagerFont(12)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(WindowsTaskManagerTheme.content)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WindowsTaskManagerTheme.separator)
                    .frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(item.properties) { property in
                        StartupPropertyRow(name: property.name, value: property.value)
                    }

                    if item.properties.isEmpty {
                        Text("No properties available")
                            .taskManagerFont(13)
                            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(WindowsTaskManagerTheme.table)
        }
        .frame(width: 560, height: 460)
    }
}

private struct StartupPropertyRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(name)
                .taskManagerFont(12, weight: .medium)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
                .padding(.leading, 20)
        }
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
