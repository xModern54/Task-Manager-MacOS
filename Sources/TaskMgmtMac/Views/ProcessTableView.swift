@preconcurrency import AppKit
import SwiftUI

struct ProcessTableView: View {
    let summary: ProcessSummary
    let rows: [ProcessTableRow]
    let sortColumn: ProcessSortColumn
    let sortDirection: SortDirection
    @Binding var selectedProcessID: ProcessMetric.ID?
    @Binding var selectedProcessGroupID: ProcessTableRow.ID?
    let onSort: (ProcessSortColumn) -> Void
    let onSelectProcess: (ProcessMetric.ID) -> Void
    let onGroupTap: (ProcessTableRow.ID) -> Void
    let onContextToggleGroup: (ProcessTableRow.ID) -> Void
    let onContextEndTask: (ProcessTableRow) -> Void
    let onContextOpenDetails: (ProcessTableRow) -> Void
    let onContextRevealFile: (ProcessTableRow) -> Void
    let onContextSearchOnline: (ProcessTableRow) -> Void
    let onScrollActivity: (Bool) -> Void
    @State private var displayedRows: [ProcessTableRow] = []
    @State private var isScrolling = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ProcessTableHeader(
                    summary: summary,
                    sortColumn: sortColumn,
                    sortDirection: sortDirection,
                    onSort: onSort
                )

                ForEach(visibleRows) { row in
                    ProcessRow(
                        row: row,
                        isSelected: row.isGroup ? selectedProcessGroupID == row.id : selectedProcessID == row.metric.id,
                        onToggleGroup: onContextToggleGroup,
                        onEndTask: onContextEndTask,
                        onOpenDetails: onContextOpenDetails,
                        onRevealFile: onContextRevealFile,
                        onSearchOnline: onContextSearchOnline
                    )
                    .onTapGesture {
                        if row.isGroup {
                            onGroupTap(row.id)
                        } else {
                            onSelectProcess(row.metric.id)
                        }
                    }
                }
            }
            .frame(minWidth: ProcessTableLayout.tableWidth, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scrollIndicators(.visible)
        .background(WindowsTaskManagerTheme.table)
        .background(
            ScrollActivityReader { scrolling in
                onScrollActivity(scrolling)
                if scrolling {
                    if !isScrolling {
                        displayedRows = rows
                    }
                    isScrolling = true
                } else {
                    isScrolling = false
                    displayedRows = rows
                }
            }
        )
        .onAppear {
            displayedRows = rows
        }
        .onChange(of: rows) { _, newRows in
            guard !isScrolling else { return }
            displayedRows = newRows
        }
    }

    private var visibleRows: [ProcessTableRow] {
        displayedRows.isEmpty ? rows : displayedRows
    }
}

private enum ProcessTableLayout {
    static let nameWidth: CGFloat = 206
    static let nameLeadingPadding: CGFloat = 22
    static let statusWidth: CGFloat = 98
    static let metricWidth: CGFloat = 101
    static let metricTrailingPadding: CGFloat = 12
    static let tableWidth = nameLeadingPadding + nameWidth + statusWidth + metricWidth * 3
}

private struct ProcessTableHeader: View {
    let summary: ProcessSummary
    let sortColumn: ProcessSortColumn
    let sortDirection: SortDirection
    let onSort: (ProcessSortColumn) -> Void

    var body: some View {
        HStack(spacing: 0) {
            HeaderNameCell()
            SummaryHeaderCell(
                value: summary.cpu,
                label: "CPU",
                isSorted: sortColumn == .cpu,
                sortDirection: sortDirection
            ) {
                onSort(.cpu)
            }
            SummaryHeaderCell(
                value: summary.memory,
                label: "Memory",
                isSorted: sortColumn == .memory,
                sortDirection: sortDirection
            ) {
                onSort(.memory)
            }
            SummaryHeaderCell(
                value: summary.disk,
                label: "Disk",
                isSorted: sortColumn == .disk,
                sortDirection: sortDirection
            ) {
                onSort(.disk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(WindowsTaskManagerTheme.table)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct HeaderNameCell: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .taskManagerFont(14)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            .frame(width: ProcessTableLayout.nameWidth, alignment: .leading)
            .padding(.leading, ProcessTableLayout.nameLeadingPadding)

            Text("Status")
                .taskManagerFont(14)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .frame(width: ProcessTableLayout.statusWidth, alignment: .leading)
        }
        .frame(height: 66)
        .overlay(alignment: .trailing) {
            CellSeparator()
        }
    }
}

private struct SummaryHeaderCell: View {
    let value: Int
    let label: String
    let isSorted: Bool
    let sortDirection: SortDirection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    if isSorted {
                        Image(systemName: sortDirection == .descending ? "chevron.down" : "chevron.up")
                            .taskManagerFont(10, weight: .semibold)
                            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                    }

                    Text("\(value)%")
                        .taskManagerFont(21)
                        .monospacedDigit()
                        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                }

                Text(label)
                    .taskManagerFont(14)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.trailing, ProcessTableLayout.metricTrailingPadding)
        .frame(width: ProcessTableLayout.metricWidth, height: 66, alignment: .trailing)
        .overlay(alignment: .trailing) {
            CellSeparator()
        }
    }
}

private struct ProcessRow: View {
    let row: ProcessTableRow
    let isSelected: Bool
    let onToggleGroup: (ProcessTableRow.ID) -> Void
    let onEndTask: (ProcessTableRow) -> Void
    let onOpenDetails: (ProcessTableRow) -> Void
    let onRevealFile: (ProcessTableRow) -> Void
    let onSearchOnline: (ProcessTableRow) -> Void
    @EnvironmentObject private var settings: TaskManagerSettings

    var body: some View {
        HStack(spacing: 0) {
            ProcessNameCell(row: row, isSelected: isSelected)
            MetricCell(text: percent(row.metric.cpu), intensity: row.metric.cpu / 10, isSelected: isSelected)
            MetricCell(text: memory(row.metric.memoryMB), intensity: row.metric.memoryMB / 1300, isSelected: isSelected)
            MetricCell(text: disk(row.metric.diskMBs), intensity: row.metric.diskMBs / 0.2, isSelected: isSelected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
        .background(isSelected ? WindowsTaskManagerTheme.tableSelection : WindowsTaskManagerTheme.table)
        .overlay {
            if isSelected {
                settings.effectiveAccentColor
                    .opacity(0.10)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if row.isGroup {
                Button(row.isExpanded ? "Collapse" : "Expand") {
                    onToggleGroup(row.id)
                }

                Divider()
            }

            Button("End task") {
                onEndTask(row)
            }

            Divider()

            Button("Go to details") {
                onOpenDetails(row)
            }

            Button("Open file location") {
                onRevealFile(row)
            }
            .disabled(row.metric.executablePath == nil)

            Button("Search online") {
                onSearchOnline(row)
            }

            Button("Properties") {
                onRevealFile(row)
            }
            .disabled(row.metric.executablePath == nil)
        }
    }

    private func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value).replacingOccurrences(of: ".", with: ",")
    }

    private func memory(_ value: Double) -> String {
        String(format: "%.1f MB", value).replacingOccurrences(of: ".", with: ",")
    }

    private func disk(_ value: Double) -> String {
        value == 0 ? "0 MB/s" : String(format: "%.1f MB/s", value).replacingOccurrences(of: ".", with: ",")
    }

}

private struct ProcessNameCell: View {
    let row: ProcessTableRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if row.isChild {
                    Color.clear
                        .frame(width: 22)
                }

                ProcessDisclosureIcon(row: row)

                ProcessIconView(process: row.metric)

                Text(displayName)
                    .taskManagerFont(14)
                    .fontWeight(row.isGroup ? .medium : .regular)
                    .lineLimit(1)
            }
            .frame(width: ProcessTableLayout.nameWidth, alignment: .leading)
            .padding(.leading, ProcessTableLayout.nameLeadingPadding)

            HStack {
                if row.metric.status == .efficiency {
                    Image(systemName: "leaf")
                        .foregroundStyle(Color(red: 0.43, green: 0.80, blue: 0.34))
                        .taskManagerFont(14)
                }
            }
            .frame(width: ProcessTableLayout.statusWidth, height: 32)
        }
        .frame(height: 32)
        .overlay(alignment: .trailing) {
            CellSeparator()
        }
    }

    private var displayName: String {
        if row.isGroup {
            return "\(row.metric.name) (\(row.childCount))"
        }

        return row.metric.name
    }
}

private struct ProcessDisclosureIcon: View {
    let row: ProcessTableRow

    var body: some View {
        Group {
            if row.isGroup {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .taskManagerFont(9, weight: .semibold)
                    .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
            } else {
                Color.clear
            }
        }
        .frame(width: 10, height: 18)
    }
}

private struct ProcessIconView: View {
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
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct MetricCell: View {
    let text: String
    let intensity: Double
    let isSelected: Bool
    @EnvironmentObject private var settings: TaskManagerSettings

    var body: some View {
        Text(text)
            .taskManagerFont(14)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.trailing, ProcessTableLayout.metricTrailingPadding)
            .frame(width: ProcessTableLayout.metricWidth, height: 32, alignment: .trailing)
            .background(background)
            .overlay(alignment: .trailing) {
                CellSeparator()
            }
    }

    private var background: Color {
        if isSelected {
            return .clear
        }

        return settings.effectiveAccentColor.opacity(0.12 + clampedIntensity * 0.16)
    }

    private var clampedIntensity: Double {
        min(max(intensity, 0), 1)
    }
}

private struct CellSeparator: View {
    var body: some View {
        Rectangle()
            .fill(WindowsTaskManagerTheme.separator)
            .frame(width: 1)
    }
}

private struct ScrollActivityReader: NSViewRepresentable {
    let onActivityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onActivityChanged = onActivityChanged
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivityChanged: onActivityChanged)
    }

    @MainActor
    final class Coordinator {
        var onActivityChanged: (Bool) -> Void
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var stopTask: Task<Void, Never>?
        private var isScrolling = false

        init(onActivityChanged: @escaping (Bool) -> Void) {
            self.onActivityChanged = onActivityChanged
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            stopTask?.cancel()
        }

        func attach(to view: NSView) {
            guard let scrollView = view.enclosingScrollView,
                  self.scrollView !== scrollView else {
                return
            }

            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }

            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.markScrolling()
                }
            }
        }

        private func markScrolling() {
            if !isScrolling {
                isScrolling = true
                onActivityChanged(true)
            }

            stopTask?.cancel()
            stopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, !Task.isCancelled else { return }
                isScrolling = false
                onActivityChanged(false)
            }
        }
    }
}
