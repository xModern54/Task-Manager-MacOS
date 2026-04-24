import Foundation

@MainActor
final class TaskManagerViewModel: ObservableObject {
    @Published private(set) var snapshot = ProcessSnapshot(
        summary: ProcessSummary(cpu: 0, memory: 0, disk: 0, network: 0, gpu: 0, processCount: 0, threadCount: 0),
        processes: []
    )
    @Published var selectedSection: TaskManagerSection = .processes
    @Published var searchText = ""
    @Published var selectedProcessID: ProcessMetric.ID?
    @Published var isSidebarExpanded = false
    @Published private(set) var sortColumn: ProcessSortColumn = .memory
    @Published private(set) var sortDirection: SortDirection = .descending

    private let refreshInterval: Duration = .milliseconds(500)
    private let monitor: any ProcessMonitoringProviding

    init(monitor: ProcessMonitoringProviding) {
        self.monitor = monitor
    }

    var visibleProcesses: [ProcessMetric] {
        let filteredProcesses: [ProcessMetric]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredProcesses = snapshot.processes
        } else {
            filteredProcesses = snapshot.processes.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || String($0.pid).contains(query)
            }
        }

        return filteredProcesses.sorted { lhs, rhs in
            sortDirection.areInIncreasingOrder(
                sortColumn.value(for: lhs),
                sortColumn.value(for: rhs),
                fallback: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            )
        }
    }

    func refresh() async {
        let nextSnapshot = await monitor.currentSnapshot()
        snapshot = nextSnapshot

        if let selectedProcessID, !nextSnapshot.processes.contains(where: { $0.id == selectedProcessID }) {
            self.selectedProcessID = nil
        }
    }

    func startRefreshing() async {
        while !Task.isCancelled {
            await refresh()

            do {
                try await Task.sleep(for: refreshInterval)
            } catch {
                break
            }
        }
    }

    func toggleSidebar() {
        isSidebarExpanded.toggle()
    }

    func sort(by column: ProcessSortColumn) {
        if sortColumn == column {
            sortDirection.toggle()
        } else {
            sortColumn = column
            sortDirection = .descending
        }
    }
}

enum ProcessSortColumn: Hashable, Sendable {
    case cpu
    case memory
    case disk

    func value(for process: ProcessMetric) -> Double {
        switch self {
        case .cpu:
            process.cpu
        case .memory:
            process.memoryMB
        case .disk:
            process.diskMBs
        }
    }
}

enum SortDirection: Hashable, Sendable {
    case ascending
    case descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }

    func areInIncreasingOrder(_ lhs: Double, _ rhs: Double, fallback: Bool) -> Bool {
        if lhs == rhs {
            return fallback
        }

        switch self {
        case .ascending:
            return lhs < rhs
        case .descending:
            return lhs > rhs
        }
    }
}

enum TaskManagerSection: String, CaseIterable, Identifiable {
    case processes = "Processes"
    case devices = "Devices"

    var id: Self { self }

    var iconSystemName: String {
        switch self {
        case .processes:
            "square.grid.2x2"
        case .devices:
            "waveform.path.ecg.rectangle"
        }
    }
}
