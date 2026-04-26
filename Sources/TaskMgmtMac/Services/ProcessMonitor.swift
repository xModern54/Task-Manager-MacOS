import Foundation

actor ProcessMonitor: ProcessMonitoringProviding {
    private let processProvider: any SystemProcessProviding
    private let memoryProvider: any SystemMemoryProviding
    private var previousCPUSamples: [Int: ProcessCPUSample] = [:]

    init(
        processProvider: SystemProcessProviding = LibprocSystemProcessProvider(),
        memoryProvider: SystemMemoryProviding = MachSystemMemoryProvider()
    ) {
        self.processProvider = processProvider
        self.memoryProvider = memoryProvider
    }

    func currentSnapshot() async -> ProcessSnapshot {
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
}

private struct ProcessMonitorSample: Sendable {
    let timestampNanoseconds: UInt64
    let activeProcessorCount: Int
    let memoryUsage: SystemMemoryUsage
    let processes: [SystemProcessInfo]
}

private struct ProcessCPUSample: Sendable {
    let timestampNanoseconds: UInt64
    let cpuTimeNanoseconds: UInt64
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
