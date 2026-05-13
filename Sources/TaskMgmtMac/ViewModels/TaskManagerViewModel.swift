import Foundation
import Darwin

@MainActor
final class TaskManagerViewModel: ObservableObject {
    @Published private(set) var snapshot = ProcessSnapshot(
        summary: ProcessSummary(cpu: 0, memory: 0, disk: 0, network: 0, gpu: 0, processCount: 0, threadCount: 0),
        processes: []
    )
    @Published var selectedSection: TaskManagerSection = .processes
    @Published var searchText = "" {
        didSet {
            rebuildVisibleProcessRows()
        }
    }
    @Published var selectedProcessID: ProcessMetric.ID?
    @Published var selectedProcessGroupID: ProcessTableRow.ID?
    @Published var expandedProcessGroupIDs: Set<String> = []
    @Published var isSidebarExpanded = false
    @Published private(set) var sortColumn: ProcessSortColumn = .memory
    @Published private(set) var sortDirection: SortDirection = .descending
    @Published private(set) var cpuHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var memoryHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var gpuHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var gpuSnapshot = SystemGPUSnapshot.unavailable
    @Published private(set) var diskHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var diskSnapshot = SystemDiskSnapshot.unavailable
    @Published private(set) var networkHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var networkSnapshot = SystemNetworkSnapshot.unavailable
    @Published private(set) var npuHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var npuSnapshot = SystemNPUSnapshot.unavailable
    @Published private(set) var batteryHistory = Array(repeating: 0.0, count: 60)
    @Published private(set) var batterySnapshot = SystemBatterySnapshot.unavailable
    @Published private(set) var cpuSensorSnapshot = SystemCPUSensorSnapshot.unavailable
    @Published private(set) var visibleProcessRows: [ProcessTableRow] = []
    @Published private(set) var processFocusScrollTargetID: ProcessMetric.ID?
    @Published var selectedPerformanceDeviceID: PerformanceDevice.ID = "cpu"

    private let historyLimit = 60
    private var refreshInterval: Duration = .milliseconds(500)
    private let monitor: any ProcessMonitoringProviding
    private let gpuInfoProvider: any SystemGPUInfoProviding
    private let diskInfoProvider: any SystemDiskInfoProviding
    private let networkInfoProvider: any SystemNetworkInfoProviding
    private let npuInfoProvider: any SystemNPUInfoProviding
    private let batteryInfoProvider: any SystemBatteryInfoProviding
    private let cpuSensorProvider: any SystemCPUSensorProviding
    private var immediateRefreshTask: Task<Void, Never>?
    private var isProcessTableScrolling = false
    private var pendingFocusedProcessID: ProcessMetric.ID?

    init(
        monitor: ProcessMonitoringProviding,
        gpuInfoProvider: SystemGPUInfoProviding = IOKitSystemGPUInfoProvider(),
        diskInfoProvider: SystemDiskInfoProviding = IOKitSystemDiskInfoProvider(),
        networkInfoProvider: SystemNetworkInfoProviding = SystemConfigurationNetworkInfoProvider(),
        npuInfoProvider: SystemNPUInfoProviding = CoreMLSystemNPUInfoProvider(),
        batteryInfoProvider: SystemBatteryInfoProviding = IOKitSystemBatteryInfoProvider(),
        cpuSensorProvider: SystemCPUSensorProviding = PowermetricsSystemCPUSensorProvider()
    ) {
        self.monitor = monitor
        self.gpuInfoProvider = gpuInfoProvider
        self.diskInfoProvider = diskInfoProvider
        self.networkInfoProvider = networkInfoProvider
        self.npuInfoProvider = npuInfoProvider
        self.batteryInfoProvider = batteryInfoProvider
        self.cpuSensorProvider = cpuSensorProvider
    }

    private func makeVisibleProcessRows(from processes: [ProcessMetric]) -> [ProcessTableRow] {
        let filtered = filteredProcesses(from: processes)
        let safariAppRoot = safariGroupRoot(in: filtered)
        let groups = Dictionary(grouping: filtered) { process in
            processAppGroup(for: process, safariAppRoot: safariAppRoot)
        }

        let groupedRows = groups.map { group, processes in
            ProcessGroupBuildResult(group: group, processes: sortedProcesses(processes))
        }
        .sorted { lhs, rhs in
            sortDirection.areInIncreasingOrder(
                sortColumn.value(for: lhs.aggregate),
                sortColumn.value(for: rhs.aggregate),
                fallback: lhs.aggregate.name.localizedCaseInsensitiveCompare(rhs.aggregate.name) == .orderedAscending
            )
        }

        return groupedRows.flatMap { result in
            guard result.group.shouldGroup, result.processes.count > 1 else {
                return result.processes.map { process in
                    ProcessTableRow(
                        id: "process-\(process.pid)",
                        kind: .process,
                        metric: process,
                        children: [],
                        isExpanded: false
                    )
                }
            }

            let isExpanded = expandedProcessGroupIDs.contains(result.group.id)
            let groupRow = ProcessTableRow(
                id: result.group.id,
                kind: .group,
                metric: result.aggregate,
                children: result.processes,
                isExpanded: isExpanded
            )

            guard isExpanded else {
                return [groupRow]
            }

            let childRows = result.processes.map { process in
                ProcessTableRow(
                    id: "\(result.group.id)-child-\(process.pid)",
                    kind: .child,
                    metric: process,
                    children: [],
                    isExpanded: false
                )
            }

            return [groupRow] + childRows
        }
    }

    private func filteredProcesses(from processes: [ProcessMetric]) -> [ProcessMetric] {
        let filteredProcesses: [ProcessMetric]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredProcesses = processes
        } else {
            filteredProcesses = processes.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || String($0.pid).contains(query)
            }
        }

        return filteredProcesses
    }

    var selectedProcess: ProcessMetric? {
        guard let selectedProcessID else { return nil }
        return snapshot.processes.first { $0.id == selectedProcessID }
    }

    var selectedProcessGroup: ProcessTableRow? {
        guard let selectedProcessGroupID else { return nil }
        return visibleProcessRows.first { $0.id == selectedProcessGroupID && $0.isGroup }
    }

    var canTerminateSelection: Bool {
        selectedProcess != nil || selectedProcessGroup != nil
    }

    var selectedTerminationTitle: String {
        if let selectedProcessGroup {
            return selectedProcessGroup.metric.name
        }

        return selectedProcess?.name ?? "task"
    }

    var selectedTerminationMessage: String {
        if let selectedProcessGroup {
            return "This will send a terminate signal to \(selectedProcessGroup.childCount) processes in \(selectedProcessGroup.metric.name)."
        }

        if let selectedProcess {
            return "This will send a terminate signal to \(selectedProcess.name). PID: \(selectedProcess.pid)."
        }

        return "No process is selected."
    }

    func terminateSelectedTask() -> ProcessTerminationResult {
        if let selectedProcessGroup {
            return terminateProcessGroup(selectedProcessGroup)
        }

        guard let process = selectedProcess else {
            return ProcessTerminationResult(isSuccess: false, message: "No process is selected.")
        }

        if process.pid == ProcessInfo.processInfo.processIdentifier {
            return ProcessTerminationResult(isSuccess: false, message: "TaskMgmtMac cannot end itself.")
        }

        let result = kill(pid_t(process.pid), SIGTERM)
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            return ProcessTerminationResult(
                isSuccess: false,
                message: "Could not end \(process.name) (\(process.pid)): \(message)"
            )
        }

        selectedProcessID = nil
        selectedProcessGroupID = nil
        return ProcessTerminationResult(
            isSuccess: true,
            message: "Sent terminate signal to \(process.name) (\(process.pid))."
        )
    }

    func selectProcess(_ processID: ProcessMetric.ID) {
        selectedProcessID = processID
        selectedProcessGroupID = nil
    }

    func focusProcess(_ processID: ProcessMetric.ID) {
        searchText = ""
        pendingFocusedProcessID = processID
        selectedSection = .processes

        if !applyPendingProcessFocusIfPossible() {
            requestImmediateRefresh()
        }
    }

    func consumeProcessFocusScrollTarget(_ processID: ProcessMetric.ID) {
        guard processFocusScrollTargetID == processID else { return }
        processFocusScrollTargetID = nil
    }

    func selectProcessRow(_ row: ProcessTableRow) {
        if row.isGroup {
            selectedProcessGroupID = row.id
            selectedProcessID = nil
        } else {
            selectedProcessID = row.metric.id
            selectedProcessGroupID = nil
        }
    }

    func selectAndToggleProcessGroup(_ groupID: ProcessTableRow.ID) {
        selectedProcessGroupID = groupID
        selectedProcessID = nil
        toggleProcessGroupExpansion(groupID)
    }

    func refresh() async {
        let shouldCollectProcessList = selectedSection == .processes
            || (selectedSection == .devices && selectedPerformanceDeviceID == "cpu")
        let shouldCollectPerformanceSamples = selectedSection == .devices
        let shouldCollectPowerSensors = selectedSection == .devices
            && ["cpu", "gpu0", "npu0", "battery0"].contains(selectedPerformanceDeviceID)

        async let monitoredSnapshot = monitor.currentSnapshot(includesProcesses: shouldCollectProcessList)
        async let currentCPUSensorSnapshot = shouldCollectPowerSensors
            ? cpuSensorProvider.snapshot(includeDetails: true)
            : cpuSensorProvider.snapshot(includeDetails: false)
        async let currentGPUSnapshot = shouldCollectPerformanceSamples
            ? gpuInfoProvider.snapshot(includeDetails: selectedPerformanceDeviceID == "gpu0")
            : SystemGPUSnapshot.unavailable
        async let currentDiskSnapshot = shouldCollectPerformanceSamples
            ? diskInfoProvider.snapshot(includeDetails: selectedPerformanceDeviceID == "disk0")
            : SystemDiskSnapshot.unavailable
        async let currentNetworkSnapshot = shouldCollectPerformanceSamples
            ? networkInfoProvider.snapshot(includeDetails: selectedPerformanceDeviceID == "ethernet")
            : SystemNetworkSnapshot.unavailable
        async let currentNPUSnapshot = shouldCollectPerformanceSamples
            ? npuInfoProvider.snapshot(includeDetails: selectedPerformanceDeviceID == "npu0")
            : SystemNPUSnapshot.unavailable
        async let currentBatterySnapshot = shouldCollectPerformanceSamples
            ? batteryInfoProvider.snapshot(includeDetails: selectedPerformanceDeviceID == "battery0")
            : SystemBatterySnapshot.unavailable

        let nextSnapshot = await monitoredSnapshot
        let nextCPUSensorSnapshot = await currentCPUSensorSnapshot
        let nextGPUSnapshot = await currentGPUSnapshot
        let nextDiskSnapshot = await currentDiskSnapshot
        let nextNetworkSnapshot = await currentNetworkSnapshot
        let nextNPUSnapshot = await currentNPUSnapshot
        let nextBatterySnapshot = await currentBatterySnapshot

        guard !Task.isCancelled else { return }

        snapshot = nextSnapshot
        if shouldCollectProcessList {
            ProcessIconCache.shared.warmIcons(for: nextSnapshot.processes)
            if !isProcessTableScrolling {
                rebuildVisibleProcessRows()
            }
            _ = applyPendingProcessFocusIfPossible()
        }
        appendCPUHistoryValue(Double(nextSnapshot.summary.cpu))
        appendMemoryHistoryValue(Double(nextSnapshot.summary.memory))

        if shouldCollectPerformanceSamples {
            gpuSnapshot = nextGPUSnapshot
            diskSnapshot = nextDiskSnapshot
            networkSnapshot = nextNetworkSnapshot
            npuSnapshot = nextNPUSnapshot
            batterySnapshot = nextBatterySnapshot
            cpuSensorSnapshot = nextCPUSensorSnapshot
            appendGPUHistoryValue(Double(nextGPUSnapshot.usagePercent))
            appendDiskHistoryValue(Double(nextDiskSnapshot.activePercent))
            appendNetworkHistoryValue(Double(nextNetworkSnapshot.throughputBytesPerSecond))
            appendNPUHistoryValue(nextCPUSensorSnapshot.anePowerWatts ?? 0)
            appendBatteryHistoryValue(Double(nextBatterySnapshot.levelPercent))
        }

        if shouldCollectProcessList,
           let selectedProcessID,
           !nextSnapshot.processes.contains(where: { $0.id == selectedProcessID }) {
            self.selectedProcessID = nil
        }

        if shouldCollectProcessList,
           let selectedProcessGroupID,
           !visibleProcessRows.contains(where: { $0.id == selectedProcessGroupID && $0.isGroup }) {
            self.selectedProcessGroupID = nil
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

    func requestImmediateRefresh() {
        immediateRefreshTask?.cancel()
        immediateRefreshTask = Task(priority: .userInitiated) { [weak self] in
            await self?.refresh()
        }
    }

    func setRefreshInterval(_ interval: SettingsRefreshInterval) {
        refreshInterval = interval.duration
    }

    func setProcessTableScrolling(_ isScrolling: Bool) {
        guard isProcessTableScrolling != isScrolling else { return }

        isProcessTableScrolling = isScrolling
        if !isScrolling {
            rebuildVisibleProcessRows()
        }
    }

    func toggleProcessGroupExpansion(_ groupID: String) {
        if expandedProcessGroupIDs.contains(groupID) {
            expandedProcessGroupIDs.remove(groupID)
        } else {
            expandedProcessGroupIDs.insert(groupID)
        }
        rebuildVisibleProcessRows()
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
        rebuildVisibleProcessRows()
    }

    private func rebuildVisibleProcessRows() {
        let rows = makeVisibleProcessRows(from: snapshot.processes)
        visibleProcessRows = rows
        ProcessIconCache.shared.warmIcons(for: rows.filter(\.isGroup).map(\.metric))
    }

    @discardableResult
    private func applyPendingProcessFocusIfPossible() -> Bool {
        guard let pendingFocusedProcessID,
              let process = snapshot.processes.first(where: { $0.id == pendingFocusedProcessID }) else {
            return false
        }

        let safariAppRoot = safariGroupRoot(in: snapshot.processes)
        let group = processAppGroup(for: process, safariAppRoot: safariAppRoot)
        if group.shouldGroup {
            expandedProcessGroupIDs.insert(group.id)
            rebuildVisibleProcessRows()
        }

        selectedProcessID = pendingFocusedProcessID
        selectedProcessGroupID = nil
        processFocusScrollTargetID = pendingFocusedProcessID
        self.pendingFocusedProcessID = nil
        return true
    }

    private func appendCPUHistoryValue(_ value: Double) {
        cpuHistory.append(value)

        if cpuHistory.count > historyLimit {
            cpuHistory.removeFirst(cpuHistory.count - historyLimit)
        }
    }

    private func appendMemoryHistoryValue(_ value: Double) {
        memoryHistory.append(value)

        if memoryHistory.count > historyLimit {
            memoryHistory.removeFirst(memoryHistory.count - historyLimit)
        }
    }

    private func appendGPUHistoryValue(_ value: Double) {
        gpuHistory.append(value)

        if gpuHistory.count > historyLimit {
            gpuHistory.removeFirst(gpuHistory.count - historyLimit)
        }
    }

    private func appendDiskHistoryValue(_ value: Double) {
        diskHistory.append(value)

        if diskHistory.count > historyLimit {
            diskHistory.removeFirst(diskHistory.count - historyLimit)
        }
    }

    private func appendNetworkHistoryValue(_ value: Double) {
        networkHistory.append(value)

        if networkHistory.count > historyLimit {
            networkHistory.removeFirst(networkHistory.count - historyLimit)
        }
    }

    private func appendNPUHistoryValue(_ value: Double) {
        npuHistory.append(value)

        if npuHistory.count > historyLimit {
            npuHistory.removeFirst(npuHistory.count - historyLimit)
        }
    }

    private func appendBatteryHistoryValue(_ value: Double) {
        batteryHistory.append(value)

        if batteryHistory.count > historyLimit {
            batteryHistory.removeFirst(batteryHistory.count - historyLimit)
        }
    }

    private func terminateProcessGroup(_ group: ProcessTableRow) -> ProcessTerminationResult {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let targetProcesses = group.children.filter { $0.pid != currentPID }

        guard !targetProcesses.isEmpty else {
            return ProcessTerminationResult(isSuccess: false, message: "No terminable processes in \(group.metric.name).")
        }

        var failedMessages: [String] = []
        for process in targetProcesses {
            let result = kill(pid_t(process.pid), SIGTERM)
            if result != 0 {
                failedMessages.append("\(process.name) (\(process.pid)): \(String(cString: strerror(errno)))")
            }
        }

        guard failedMessages.isEmpty else {
            return ProcessTerminationResult(
                isSuccess: false,
                message: "Could not end all processes in \(group.metric.name): \(failedMessages.joined(separator: "; "))"
            )
        }

        selectedProcessID = nil
        selectedProcessGroupID = nil
        expandedProcessGroupIDs.remove(group.id)

        return ProcessTerminationResult(
            isSuccess: true,
            message: "Sent terminate signal to \(targetProcesses.count) processes in \(group.metric.name)."
        )
    }

    private func sortedProcesses(_ processes: [ProcessMetric]) -> [ProcessMetric] {
        processes.sorted { lhs, rhs in
            sortDirection.areInIncreasingOrder(
                sortColumn.value(for: lhs),
                sortColumn.value(for: rhs),
                fallback: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            )
        }
    }

    private func processAppGroup(
        for process: ProcessMetric,
        safariAppRoot: (path: String, name: String)?
    ) -> ProcessAppGroup {
        if isSafariWebKitAuxiliaryProcess(process),
           let safariAppRoot {
            return ProcessAppGroup(
                id: "app-\(safariAppRoot.path)",
                name: safariAppRoot.name,
                executablePath: safariAppRoot.path,
                shouldGroup: true
            )
        }

        guard let executablePath = process.executablePath,
              let appRoot = appBundleRoot(from: executablePath) else {
            return ProcessAppGroup(
                id: "pid-\(process.pid)",
                name: process.name,
                executablePath: process.executablePath,
                shouldGroup: false
            )
        }

        return ProcessAppGroup(
            id: "app-\(appRoot.path)",
            name: appRoot.name,
            executablePath: appRoot.path,
            shouldGroup: true
        )
    }

    private func safariGroupRoot(in processes: [ProcessMetric]) -> (path: String, name: String)? {
        for process in processes {
            guard process.name.caseInsensitiveCompare("Safari") == .orderedSame,
                  let executablePath = process.executablePath,
                  let appRoot = appBundleRoot(from: executablePath) else {
                continue
            }

            return appRoot
        }

        return nil
    }

    private func isSafariWebKitAuxiliaryProcess(_ process: ProcessMetric) -> Bool {
        guard process.name.hasPrefix("com.apple.WebKit.") else {
            return false
        }

        guard let executablePath = process.executablePath else {
            return false
        }

        return executablePath.contains("/System/Library/Frameworks/WebKit.framework/")
            && executablePath.contains("/XPCServices/com.apple.WebKit.")
    }

    private func appBundleRoot(from executablePath: String) -> (path: String, name: String)? {
        let components = URL(fileURLWithPath: executablePath).pathComponents
        var pathComponents: [String] = []

        for component in components {
            pathComponents.append(component)

            guard component.hasSuffix(".app") else {
                continue
            }

            let path = NSString.path(withComponents: pathComponents)
            let name = String(component.dropLast(4))
            return (path, name)
        }

        return nil
    }
}

struct ProcessTerminationResult: Sendable {
    let isSuccess: Bool
    let message: String
}

private struct ProcessAppGroup: Hashable {
    let id: String
    let name: String
    let executablePath: String?
    let shouldGroup: Bool
}

private struct ProcessGroupBuildResult {
    let group: ProcessAppGroup
    let processes: [ProcessMetric]

    var aggregate: ProcessMetric {
        guard let representative = processes.first else {
            return ProcessMetric(
                name: group.name,
                iconSystemName: "app",
                executablePath: group.executablePath,
                group: .apps,
                cpu: 0,
                memoryMB: 0,
                diskMBs: 0,
                networkMbps: 0,
                powerUsage: .veryLow,
                gpu: 0,
                pid: 0
            )
        }

        return ProcessMetric(
            name: group.shouldGroup ? group.name : representative.name,
            iconSystemName: representative.iconSystemName,
            executablePath: group.executablePath ?? representative.executablePath,
            group: representative.group,
            childCount: group.shouldGroup ? processes.count : nil,
            status: processes.contains(where: { $0.status == .efficiency }) ? .efficiency : nil,
            cpu: min(processes.reduce(0) { $0 + $1.cpu }, 100),
            memoryMB: processes.reduce(0) { $0 + $1.memoryMB },
            diskMBs: processes.reduce(0) { $0 + $1.diskMBs },
            networkMbps: processes.reduce(0) { $0 + $1.networkMbps },
            powerUsage: representative.powerUsage,
            gpu: processes.reduce(0) { $0 + $1.gpu },
            pid: representative.pid
        )
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
    case startupApps = "Startup apps"
    case services = "Services"
    case settings = "Settings"

    var id: Self { self }

    var iconSystemName: String {
        switch self {
        case .processes:
            "square.grid.2x2"
        case .devices:
            "waveform.path.ecg.rectangle"
        case .startupApps:
            "speedometer"
        case .services:
            "switch.2"
        case .settings:
            "gearshape"
        }
    }
}
