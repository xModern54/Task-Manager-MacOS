@preconcurrency import AppKit
import SwiftUI

@MainActor
final class ProcessDetailsWindowPresenter {
    static let shared = ProcessDetailsWindowPresenter()

    private var windows: [String: NSWindow] = [:]

    private init() {}

    func open(row: ProcessTableRow) {
        let windowKey = row.isGroup ? row.id : "process-\(row.metric.pid)"

        if let window = windows[windowKey] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(row.metric.name) details"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProcessDetailsWindow(row: row))

        windows[windowKey] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ProcessDetailsWindow: View {
    let row: ProcessTableRow
    @State private var selectedTab: ProcessDetailsTab = .main

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar

            Divider()

            tabContent
        }
        .frame(minWidth: 680, minHeight: 620)
        .background(WindowsTaskManagerTheme.content)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
    }

    private var header: some View {
        HStack(spacing: 18) {
            ProcessDetailsIcon(process: row.metric, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.metric.name)
                    .taskManagerFont(28, weight: .semibold)
                    .lineLimit(1)

                Text(row.metric.executablePath ?? "Executable path unavailable")
                    .taskManagerFont(13)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    ProcessDetailBadge(text: "PID \(row.metric.pid)")
                    ProcessDetailBadge(text: rowKind)

                    if row.isGroup {
                        ProcessDetailBadge(text: "\(row.childCount) processes")
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .background(WindowsTaskManagerTheme.content)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProcessDetailsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 10) {
                        Text(tab.title)
                            .taskManagerFont(15, weight: selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(selectedTab == tab ? WindowsTaskManagerTheme.textPrimary : WindowsTaskManagerTheme.textSecondary)
                            .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(selectedTab == tab ? WindowsTaskManagerTheme.accent : .clear)
                            .frame(height: 3)
                    }
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .background(WindowsTaskManagerTheme.content)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .main:
            ProcessDetailsMainTab(row: row, rowKind: rowKind)
        case .stats:
            ProcessDetailsStatsTab(row: row)
        case .modules:
            ProcessDetailsModulesTab(row: row)
        case .threads:
            ProcessDetailsThreadsTab(row: row)
        }
    }

    private var rowKind: String {
        switch row.kind {
        case .process:
            "Process"
        case .group:
            "Application group"
        case .child:
            "Grouped process"
        }
    }
}

private enum ProcessDetailsTab: String, CaseIterable, Identifiable {
    case main
    case stats
    case modules
    case threads

    var id: Self { self }

    var title: String {
        switch self {
        case .main:
            "Main"
        case .stats:
            "Stats"
        case .modules:
            "Modules"
        case .threads:
            "Threads"
        }
    }
}

private struct ProcessDetailsMainTab: View {
    let row: ProcessTableRow
    let rowKind: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ProcessStatTile(title: "CPU", value: percent(row.metric.cpu), subtitle: "Current process usage")
                    ProcessStatTile(title: "Memory", value: memory(row.metric.memoryMB), subtitle: "Resident memory")
                    ProcessStatTile(title: "Disk", value: disk(row.metric.diskMBs), subtitle: "Current throughput")
                    ProcessStatTile(title: "Power", value: row.metric.powerUsage.rawValue, subtitle: "Estimated usage")
                }

                DetailSection(title: "Identity") {
                    DetailRow(label: "Name", value: row.metric.name)
                    DetailRow(label: "PID", value: "\(row.metric.pid)")
                    DetailRow(label: "Kind", value: rowKind)
                    DetailRow(label: "Executable", value: row.metric.executablePath ?? "Unavailable")
                }

                if row.isGroup {
                    DetailSection(title: "Grouped processes") {
                        ForEach(row.children) { process in
                            DetailRow(label: process.name, value: "PID \(process.pid)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(WindowsTaskManagerTheme.table)
    }

    private func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value)
    }

    private func memory(_ value: Double) -> String {
        String(format: "%.1f MB", value)
    }

    private func disk(_ value: Double) -> String {
        value == 0 ? "0 MB/s" : String(format: "%.1f MB/s", value)
    }

    private func network(_ value: Double) -> String {
        value == 0 ? "0 Mbps" : String(format: "%.1f Mbps", value)
    }
}

private struct ProcessDetailsStatsTab: View {
    let row: ProcessTableRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailSection(title: "Resource usage") {
                    DetailRow(label: "CPU", value: percent(row.metric.cpu))
                    DetailRow(label: "Memory", value: memory(row.metric.memoryMB))
                    DetailRow(label: "Disk", value: disk(row.metric.diskMBs))
                    DetailRow(label: "Network", value: network(row.metric.networkMbps))
                    DetailRow(label: "GPU", value: percent(row.metric.gpu))
                    DetailRow(label: "Power usage", value: row.metric.powerUsage.rawValue)
                }

                DetailSection(title: "Kernel activity") {
                    DetailRow(label: "Context switches", value: "Provider pending")
                    DetailRow(label: "Mach syscalls", value: "Provider pending")
                    DetailRow(label: "Unix syscalls", value: "Provider pending")
                    DetailRow(label: "Page faults", value: "Provider pending")
                    DetailRow(label: "Mach messages", value: "Provider pending")
                }
            }
            .padding(24)
        }
        .background(WindowsTaskManagerTheme.table)
    }

    private func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value)
    }

    private func memory(_ value: Double) -> String {
        String(format: "%.1f MB", value)
    }

    private func disk(_ value: Double) -> String {
        value == 0 ? "0 MB/s" : String(format: "%.1f MB/s", value)
    }

    private func network(_ value: Double) -> String {
        value == 0 ? "0 Mbps" : String(format: "%.1f Mbps", value)
    }
}

private struct ProcessDetailsModulesTab: View {
    let row: ProcessTableRow

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let executablePath = row.metric.executablePath {
                    ProcessModuleRow(
                        name: URL(fileURLWithPath: executablePath).lastPathComponent,
                        path: executablePath,
                        detail: "Main executable",
                        sizeText: diskSize(for: executablePath)
                    )
                }

                if let bundlePath = appBundlePath(from: row.metric.executablePath) {
                    ProcessModuleRow(
                        name: URL(fileURLWithPath: bundlePath).lastPathComponent,
                        path: bundlePath,
                        detail: "Application bundle",
                        sizeText: diskSize(for: bundlePath)
                    )
                }

                ProcessModuleRow(
                    name: "Dynamic libraries",
                    path: "Module provider pending",
                    detail: "dylib, framework, bundle, and mapped file regions",
                    sizeText: "Soon"
                )

                ProcessModuleRow(
                    name: "Memory mapped files",
                    path: "VM region provider pending",
                    detail: "Mapped size and resident memory per file",
                    sizeText: "Soon"
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(WindowsTaskManagerTheme.table)
    }

    private func appBundlePath(from executablePath: String?) -> String? {
        guard let executablePath else { return nil }

        let components = URL(fileURLWithPath: executablePath).pathComponents
        var pathComponents: [String] = []

        for component in components {
            pathComponents.append(component)

            guard component.hasSuffix(".app") else {
                continue
            }

            return NSString.path(withComponents: pathComponents)
        }

        return nil
    }

    private func diskSize(for path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return "Unknown"
        }

        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }
}

private struct ProcessDetailsThreadsTab: View {
    let row: ProcessTableRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailSection(title: "Thread summary") {
                    DetailRow(label: "Thread count", value: row.isGroup ? "Grouped process provider pending" : "Provider pending")
                    DetailRow(label: "Running threads", value: "Provider pending")
                    DetailRow(label: "Highest CPU thread", value: "Provider pending")
                }

                LazyVStack(spacing: 0) {
                    ProcessThreadPreviewRow(name: "Thread list", state: "Provider pending", cpu: "Soon", priority: "Soon")
                    ProcessThreadPreviewRow(name: "Per-thread CPU", state: "Design ready", cpu: "Soon", priority: "Soon")
                    ProcessThreadPreviewRow(name: "Per-thread priority", state: "Design ready", cpu: "Soon", priority: "Soon")
                }
            }
            .padding(24)
        }
        .background(WindowsTaskManagerTheme.table)
    }
}

private struct ProcessDetailBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .taskManagerFont(12, weight: .medium)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(WindowsTaskManagerTheme.searchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct ProcessStatTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .taskManagerFont(12, weight: .semibold)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            Text(value)
                .taskManagerFont(24, weight: .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(WindowsTaskManagerTheme.content)
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WindowsTaskManagerTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct ProcessDetailsIcon: View {
    let process: ProcessMetric
    let size: CGFloat
    @ObservedObject private var iconCache = ProcessIconCache.shared

    var body: some View {
        Group {
            if let icon = iconCache.cachedIcon(pid: process.pid, executablePath: process.executablePath) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: process.iconSystemName)
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

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .taskManagerFont(13, weight: .semibold)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            VStack(spacing: 0) {
                content
            }
            .background(WindowsTaskManagerTheme.table)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(WindowsTaskManagerTheme.separator, lineWidth: 1)
            }
        }
    }
}

private struct ProcessModuleRow: View {
    let name: String
    let path: String
    let detail: String
    let sizeText: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .taskManagerFont(15, weight: .semibold)
                    .lineLimit(1)

                Text(path)
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .taskManagerFont(11)
                    .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(sizeText)
                .taskManagerFont(15, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(WindowsTaskManagerTheme.accent)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct ProcessThreadPreviewRow: View {
    let name: String
    let state: String
    let cpu: String
    let priority: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .taskManagerFont(14, weight: .semibold)
                    .lineLimit(1)

                Text(state)
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(cpu)
                .taskManagerFont(13, weight: .medium)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            Text(priority)
                .taskManagerFont(13, weight: .medium)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: 130, alignment: .leading)

            Text(value)
                .taskManagerFont(13)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}
