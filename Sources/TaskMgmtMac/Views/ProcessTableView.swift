import SwiftUI

struct ProcessTableView: View {
    let summary: ProcessSummary
    let processes: [ProcessMetric]
    let sortColumn: ProcessSortColumn
    let sortDirection: SortDirection
    @Binding var selectedProcessID: ProcessMetric.ID?
    let onSort: (ProcessSortColumn) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ProcessTableHeader(
                    summary: summary,
                    sortColumn: sortColumn,
                    sortDirection: sortDirection,
                    onSort: onSort
                )

                ForEach(processes) { process in
                    ProcessRow(
                        process: process,
                        isSelected: selectedProcessID == process.id
                    )
                    .onTapGesture {
                        selectedProcessID = process.id
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
    let process: ProcessMetric
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            ProcessNameCell(process: process, isSelected: isSelected)
            MetricCell(text: percent(process.cpu), intensity: process.cpu / 10, isSelected: isSelected)
            MetricCell(text: memory(process.memoryMB), intensity: process.memoryMB / 1300, isSelected: isSelected)
            MetricCell(text: disk(process.diskMBs), intensity: process.diskMBs / 0.2, isSelected: isSelected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
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
    let process: ProcessMetric
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(process: process)

                Text(displayName)
                    .taskManagerFont(14)
                    .lineLimit(1)
            }
            .frame(width: ProcessTableLayout.nameWidth, alignment: .leading)
            .padding(.leading, ProcessTableLayout.nameLeadingPadding)

            HStack {
                if process.status == .efficiency {
                    Image(systemName: "leaf")
                        .foregroundStyle(Color(red: 0.43, green: 0.80, blue: 0.34))
                        .taskManagerFont(14)
                }
            }
            .frame(width: ProcessTableLayout.statusWidth, height: 32)
        }
        .frame(height: 32)
        .background(isSelected ? WindowsTaskManagerTheme.tableSelection : WindowsTaskManagerTheme.table)
        .overlay(alignment: .trailing) {
            CellSeparator()
        }
    }

    private var displayName: String {
        process.name
    }
}

private struct ProcessIconView: View {
    let process: ProcessMetric

    var body: some View {
        Image(nsImage: ProcessIconCache.shared.icon(pid: process.pid, executablePath: process.executablePath))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

private struct MetricCell: View {
    let text: String
    let intensity: Double
    let isSelected: Bool

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
            return WindowsTaskManagerTheme.metricHeatStrong
        }

        return WindowsTaskManagerTheme.metricHeat.opacity(0.72 + min(max(intensity, 0), 1) * 0.28)
    }
}

private struct CellSeparator: View {
    var body: some View {
        Rectangle()
            .fill(WindowsTaskManagerTheme.separator)
            .frame(width: 1)
    }
}
