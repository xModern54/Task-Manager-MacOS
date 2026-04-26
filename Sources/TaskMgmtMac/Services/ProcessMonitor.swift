import Darwin
import Foundation

actor ProcessMonitor: ProcessMonitoringProviding {
    private let processProvider: any SystemProcessProviding
    private let memoryProvider: any SystemMemoryProviding
    private var previousCPUSamples: [Int: ProcessCPUSample] = [:]
    private var previousSystemCPUSample: SystemCPUSample?

    init(
        processProvider: SystemProcessProviding = LibprocSystemProcessProvider(),
        memoryProvider: SystemMemoryProviding = MachSystemMemoryProvider()
    ) {
        self.processProvider = processProvider
        self.memoryProvider = memoryProvider
    }

    func currentSnapshot(includesProcesses: Bool) async -> ProcessSnapshot {
        if !includesProcesses {
            return await currentSummarySnapshot()
        }

        let processProvider = self.processProvider
        let memoryProvider = self.memoryProvider

        let sample = await Task.detached(priority: .utility) {
            let processes = processProvider.processes()
            let memoryUsage = memoryProvider.usage()
            return ProcessMonitorSample(
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                activeProcessorCount: max(ProcessInfo.processInfo.activeProcessorCount, 1),
                memoryUsage: memoryUsage,
                processes: processes
            )
        }.value

        var nextCPUSamples: [Int: ProcessCPUSample] = [:]
        var totalCPUPercent = 0.0
        let metrics = sample.processes.map { process in
            let cpuPercent = cpuPercent(for: process, sample: sample)
            nextCPUSamples[process.pid] = ProcessCPUSample(
                timestampNanoseconds: sample.timestampNanoseconds,
                cpuTimeNanoseconds: process.cpuTimeNanoseconds
            )
            totalCPUPercent += cpuPercent

            return ProcessMetric(systemProcess: process, cpu: cpuPercent)
        }

        previousCPUSamples = nextCPUSamples
        previousSystemCPUSample = SystemCPUSample(
            timestampNanoseconds: sample.timestampNanoseconds,
            ticks: ProcessMonitor.systemCPUTicks()
        )

        return ProcessSnapshot(
            summary: ProcessSummary(
                cpu: min(Int(totalCPUPercent.rounded()), 100),
                memory: sample.memoryUsage.usagePercent,
                memoryUsedBytes: sample.memoryUsage.usedBytes,
                memoryTotalBytes: sample.memoryUsage.totalBytes,
                memoryCompressedBytes: sample.memoryUsage.compressedBytes,
                disk: 0,
                network: 0,
                gpu: 0,
                processCount: sample.processes.count,
                threadCount: sample.processes.reduce(0) { $0 + $1.threadCount }
            ),
            processes: metrics
        )
    }

    private func currentSummarySnapshot() async -> ProcessSnapshot {
        let memoryProvider = self.memoryProvider

        let sample = await Task.detached(priority: .utility) {
            ProcessMonitorSummarySample(
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                memoryUsage: memoryProvider.usage(),
                cpuTicks: ProcessMonitor.systemCPUTicks()
            )
        }.value

        let cpuPercent = systemCPUPercent(for: sample)
        previousSystemCPUSample = SystemCPUSample(
            timestampNanoseconds: sample.timestampNanoseconds,
            ticks: sample.cpuTicks
        )

        return ProcessSnapshot(
            summary: ProcessSummary(
                cpu: cpuPercent,
                memory: sample.memoryUsage.usagePercent,
                memoryUsedBytes: sample.memoryUsage.usedBytes,
                memoryTotalBytes: sample.memoryUsage.totalBytes,
                memoryCompressedBytes: sample.memoryUsage.compressedBytes,
                disk: 0,
                network: 0,
                gpu: 0,
                processCount: snapshotProcessCountFallback,
                threadCount: 0
            ),
            processes: []
        )
    }

    private func cpuPercent(for process: SystemProcessInfo, sample: ProcessMonitorSample) -> Double {
        guard let previousSample = previousCPUSamples[process.pid] else { return 0 }
        guard process.cpuTimeNanoseconds >= previousSample.cpuTimeNanoseconds,
              sample.timestampNanoseconds >= previousSample.timestampNanoseconds else {
            return 0
        }

        let elapsedNanoseconds = sample.timestampNanoseconds - previousSample.timestampNanoseconds
        let processNanoseconds = process.cpuTimeNanoseconds - previousSample.cpuTimeNanoseconds
        guard elapsedNanoseconds > 0 else { return 0 }

        let rawPercent = Double(processNanoseconds) / Double(elapsedNanoseconds) * 100
        let normalizedPercent = rawPercent / Double(sample.activeProcessorCount)
        return min(max(normalizedPercent, 0), 100)
    }

    private var snapshotProcessCountFallback: Int {
        previousCPUSamples.count
    }

    private func systemCPUPercent(for sample: ProcessMonitorSummarySample) -> Int {
        guard let previousSystemCPUSample else { return 0 }

        let previous = previousSystemCPUSample.ticks
        let current = sample.cpuTicks
        let userDelta = current.user >= previous.user ? current.user - previous.user : 0
        let systemDelta = current.system >= previous.system ? current.system - previous.system : 0
        let niceDelta = current.nice >= previous.nice ? current.nice - previous.nice : 0
        let idleDelta = current.idle >= previous.idle ? current.idle - previous.idle : 0
        let activeDelta = userDelta + systemDelta + niceDelta
        let totalDelta = activeDelta + idleDelta

        guard totalDelta > 0 else { return 0 }
        return min(max(Int((Double(activeDelta) / Double(totalDelta) * 100).rounded()), 0), 100)
    }

    private static func systemCPUTicks() -> SystemCPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return SystemCPUTicks(user: 0, system: 0, nice: 0, idle: 0)
        }

        return SystemCPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            nice: UInt64(info.cpu_ticks.2),
            idle: UInt64(info.cpu_ticks.3)
        )
    }
}

private struct ProcessMonitorSample: Sendable {
    let timestampNanoseconds: UInt64
    let activeProcessorCount: Int
    let memoryUsage: SystemMemoryUsage
    let processes: [SystemProcessInfo]
}

private struct ProcessMonitorSummarySample: Sendable {
    let timestampNanoseconds: UInt64
    let memoryUsage: SystemMemoryUsage
    let cpuTicks: SystemCPUTicks
}

private struct ProcessCPUSample: Sendable {
    let timestampNanoseconds: UInt64
    let cpuTimeNanoseconds: UInt64
}

private struct SystemCPUSample: Sendable {
    let timestampNanoseconds: UInt64
    let ticks: SystemCPUTicks
}

private struct SystemCPUTicks: Sendable {
    let user: UInt64
    let system: UInt64
    let nice: UInt64
    let idle: UInt64
}

private extension ProcessMetric {
    init(systemProcess: SystemProcessInfo, cpu: Double) {
        self.init(
            name: systemProcess.name,
            iconSystemName: "app.dashed",
            executablePath: systemProcess.executablePath,
            group: .backgroundProcesses,
            cpu: cpu,
            memoryMB: Double(systemProcess.residentMemoryBytes) / 1024 / 1024,
            diskMBs: 0,
            networkMbps: 0,
            powerUsage: .veryLow,
            gpu: 0,
            pid: systemProcess.pid
        )
    }
}
