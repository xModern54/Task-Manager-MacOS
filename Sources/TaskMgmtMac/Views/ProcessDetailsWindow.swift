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
                .focusable(false)
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
    @State private var modules: [ProcessModuleInfo] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            moduleSummary

            Divider()

            if isLoading {
                loadingView
            } else if modules.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(modules) { module in
                            ProcessModuleRow(module: module)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(WindowsTaskManagerTheme.table)
        .task(id: row.metric.pid) {
            await loadModules()
        }
    }

    private var moduleSummary: some View {
        HStack(spacing: 14) {
            Text("Loaded modules")
                .taskManagerFont(14, weight: .semibold)

            Spacer()

            Text(summaryText)
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(WindowsTaskManagerTheme.table)
    }

    private var summaryText: String {
        if isLoading {
            return "Scanning memory map..."
        }

        let residentBytes = modules.reduce(UInt64(0)) { $0 + $1.residentBytes }
        return "\(modules.count) items · \(byteCount(residentBytes)) resident"
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Scanning memory mapped files")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("No mapped modules found")
                .taskManagerFont(15, weight: .semibold)

            Text("macOS did not return readable mapped file paths for this process.")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func loadModules() async {
        isLoading = true
        modules = []

        let pid = row.metric.pid
        let executablePath = row.metric.executablePath
        let loadedModules = await Task.detached(priority: .utility) {
            LibprocProcessModuleProvider().modules(for: pid, executablePath: executablePath)
        }.value

        guard !Task.isCancelled else { return }

        modules = loadedModules
        isLoading = false
    }

    private func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

private struct ProcessDetailsThreadsTab: View {
    let row: ProcessTableRow
    @State private var threads: [ProcessThreadInfo] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            threadSummary

            Divider()

            if isLoading {
                loadingView
            } else if threads.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ProcessThreadListHeader()

                        ForEach(threads) { thread in
                            ProcessThreadPreviewRow(thread: thread)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(WindowsTaskManagerTheme.table)
        .task(id: row.metric.pid) {
            await refreshLoop()
        }
    }

    private var threadSummary: some View {
        HStack(spacing: 14) {
            Text("Threads")
                .taskManagerFont(14, weight: .semibold)

            Spacer()

            Text(summaryText)
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(WindowsTaskManagerTheme.table)
    }

    private var summaryText: String {
        if isLoading {
            return "Loading thread activity..."
        }

        let totalCPU = threads.reduce(0) { $0 + $1.cpuPercent }
        return "\(threads.count) threads · \(percent(totalCPU)) CPU"
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading per-thread CPU and priority")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("No thread data available")
                .taskManagerFont(15, weight: .semibold)

            Text("macOS did not return readable thread information for this process.")
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func refreshLoop() async {
        isLoading = true
        threads = []

        while !Task.isCancelled {
            await loadThreads()

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break
            }
        }
    }

    private func loadThreads() async {
        let pid = row.metric.pid
        let loadedThreads = await Task.detached(priority: .utility) {
            LibprocProcessThreadProvider().threads(for: pid)
        }.value

        guard !Task.isCancelled else { return }

        threads = loadedThreads
        isLoading = false
    }

    private func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value)
    }
}

private struct ProcessThreadListHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("CPU")
                .frame(width: 76, alignment: .trailing)

            Text("Priority")
                .frame(width: 86, alignment: .trailing)
        }
        .taskManagerFont(12, weight: .semibold)
        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
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
    let module: ProcessModuleInfo

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.name)
                    .taskManagerFont(15, weight: .semibold)
                    .lineLimit(1)

                Text(module.path)
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText)
                    .taskManagerFont(11)
                    .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(byteCount(module.residentBytes))
                    .taskManagerFont(15, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(WindowsTaskManagerTheme.accent)

                Text("resident")
                    .taskManagerFont(11)
                    .foregroundStyle(WindowsTaskManagerTheme.textMuted)
            }
            .frame(width: 108, alignment: .trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }

    private var detailText: String {
        let diskText = module.diskBytes.map { "disk \(byteCount($0))" } ?? "disk unknown"
        return "\(module.kind.rawValue) · mapped \(byteCount(module.mappedBytes)) · \(module.regionCount) regions · \(module.protectionSummary) · \(diskText)"
    }

    private func byteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}

private struct ProcessThreadPreviewRow: View {
    let thread: ProcessThreadInfo

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displayName)
                    .taskManagerFont(14, weight: .semibold)
                    .lineLimit(1)

                Text(detailText)
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(percent(thread.cpuPercent))
                .taskManagerFont(13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(WindowsTaskManagerTheme.accent)
                .frame(width: 76, alignment: .trailing)

            Text("\(thread.currentPriority)")
                .taskManagerFont(13, weight: .medium)
                .monospacedDigit()
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }

    private var detailText: String {
        "ID \(thread.threadID) · \(thread.state.rawValue) · base \(thread.basePriority) · max \(thread.maxPriority) · policy \(thread.policy)"
    }

    private func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value)
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
