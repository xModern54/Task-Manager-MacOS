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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DetailSection(title: "Identity") {
                        DetailRow(label: "Name", value: row.metric.name)
                        DetailRow(label: "PID", value: "\(row.metric.pid)")
                        DetailRow(label: "Kind", value: rowKind)
                        DetailRow(label: "Executable", value: row.metric.executablePath ?? "Unavailable")
                    }

                    DetailSection(title: "Resource usage") {
                        DetailRow(label: "CPU", value: percent(row.metric.cpu))
                        DetailRow(label: "Memory", value: memory(row.metric.memoryMB))
                        DetailRow(label: "Disk", value: disk(row.metric.diskMBs))
                        DetailRow(label: "Network", value: network(row.metric.networkMbps))
                        DetailRow(label: "GPU", value: percent(row.metric.gpu))
                        DetailRow(label: "Power usage", value: row.metric.powerUsage.rawValue)
                    }

                    if row.isGroup {
                        DetailSection(title: "Grouped processes") {
                            ForEach(row.children) { process in
                                DetailRow(label: process.name, value: "PID \(process.pid)")
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 560, minHeight: 430)
        .background(WindowsTaskManagerTheme.content)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProcessDetailsIcon(process: row.metric)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.metric.name)
                    .taskManagerFont(18, weight: .semibold)
                    .lineLimit(1)

                Text(row.metric.executablePath ?? "Executable path unavailable")
                    .taskManagerFont(12)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(WindowsTaskManagerTheme.content)
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

private struct ProcessDetailsIcon: View {
    let process: ProcessMetric
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
        .frame(width: 34, height: 34)
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
