import Foundation

struct MockProcessMonitor: ProcessMonitoringProviding, Sendable {
    func currentSnapshot(includesProcesses: Bool) async -> ProcessSnapshot {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let usedBytes = UInt64(Double(totalBytes) * 0.54)
        return ProcessSnapshot(
            summary: ProcessSummary(
                cpu: 92,
                memory: 54,
                memoryUsedBytes: usedBytes,
                memoryTotalBytes: totalBytes,
                memoryCompressedBytes: 0,
                memoryCachedBytes: UInt64(Double(totalBytes) * 0.18),
                memoryWiredBytes: UInt64(Double(totalBytes) * 0.08),
                memorySwapUsedBytes: 0,
                memorySwapTotalBytes: 0,
                disk: 1,
                network: 0,
                gpu: 0,
                processCount: Self.processes.count,
                threadCount: 1741
            ),
            processes: includesProcesses ? Self.processes : []
        )
    }
}

extension MockProcessMonitor {
    static let processes: [ProcessMetric] = [
        ProcessMetric(name: "Microsoft Edge", iconSystemName: "globe", group: .apps, status: .efficiency, cpu: 8.4, memoryMB: 1275.5, diskMBs: 0.1, networkMbps: 0.0, powerUsage: .high, gpu: 0.0, pid: 4022),
        ProcessMetric(name: "Microsoft Outlook", iconSystemName: "envelope.fill", group: .apps, cpu: 1.9, memoryMB: 200.4, diskMBs: 0.1, networkMbps: 0.0, powerUsage: .low, gpu: 0.0, pid: 702),
        ProcessMetric(name: "Outlook (new)", iconSystemName: "mail.stack.fill", group: .apps, cpu: 0.7, memoryMB: 456.7, diskMBs: 0.0, networkMbps: 0.0, powerUsage: .veryLow, gpu: 0.0, pid: 9301),
        ProcessMetric(name: "PowerShell executable for Ide...", iconSystemName: "terminal.fill", group: .apps, cpu: 0.0, memoryMB: 2.0, diskMBs: 0.0, networkMbps: 0.0, powerUsage: .veryLow, gpu: 0.0, pid: 441),
        ProcessMetric(name: "Skype", iconSystemName: "video.fill", group: .apps, cpu: 2.4, memoryMB: 146.6, diskMBs: 0.0, networkMbps: 0.0, powerUsage: .veryLow, gpu: 0.0, pid: 8821),
        ProcessMetric(name: "Snipping Tool", iconSystemName: "scissors", group: .apps, cpu: 0.0, memoryMB: 65.3, diskMBs: 0.0, networkMbps: 0.0, powerUsage: .veryLow, gpu: 0.0, pid: 6300),
        ProcessMetric(name: "Task Manager", iconSystemName: "waveform.path.ecg.rectangle.fill", group: .apps, cpu: 0.6, memoryMB: 30.6, diskMBs: 0.0, networkMbps: 0.0, powerUsage: .high, gpu: 0.0, pid: 1210)
    ]
}
