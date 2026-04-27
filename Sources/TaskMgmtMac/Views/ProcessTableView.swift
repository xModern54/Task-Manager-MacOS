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

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ProcessTableHeader(
                    summary: summary,
                    sortColumn: sortColumn,
                    sortDirection: sortDirection,
                    onSort: onSort
                )

                ForEach(rows) { row in
                    ProcessRow(
                        row: row,
                        isSelected: row.isGroup ? selectedProcessGroupID == row.id : selectedProcessID == row.metric.id
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
            Button("Expand") {}
            Button("Switch to") {}
                .disabled(true)
            Button("End task") {}
            Menu("Resource values") {
                Button("Percents") {}
                Button("Values") {}
            }
            Divider()
            Button("Debug") {}
                .disabled(true)
            Button("Create memory dump file") {}
                .disabled(true)
            Divider()
            Button("Go to details") {}
            Button("Open file location") {}
            Button("Search online") {}
            Button("Properties") {}
                .disabled(true)
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
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
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
        .task(id: iconTaskID) {
            if let cachedIcon = ProcessIconCache.shared.cachedIcon(pid: process.pid, executablePath: process.executablePath) {
                icon = cachedIcon
                return
            }

            icon = nil
            await Task.yield()
            icon = ProcessIconCache.shared.icon(pid: process.pid, executablePath: process.executablePath)
        }
    }

    private var iconTaskID: String {
        "\(process.pid):\(process.executablePath ?? "")"
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
