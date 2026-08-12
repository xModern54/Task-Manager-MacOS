import Darwin
import Foundation
import IOKit
import IOKit.kext

actor MachKernelMonitor: KernelMonitoringProviding {
    private let extensionRefreshInterval: TimeInterval = 10
    private let serviceRefreshInterval: TimeInterval = 5

    private var previousSystemSample: KernelSystemSample?
    private var cachedIdentity: KernelIdentity?
    private var cachedExtensionStats = KernelExtensionStats.empty
    private var extensionStatsDate = Date.distantPast
    private var cachedIOServiceCount = 0
    private var ioServiceCountDate = Date.distantPast

    func snapshot() async -> KernelSnapshot {
        let now = Date()
        let shouldCaptureIdentity = cachedIdentity == nil
        let shouldRefreshExtensions = now.timeIntervalSince(extensionStatsDate) >= extensionRefreshInterval
        let shouldRefreshServices = now.timeIntervalSince(ioServiceCountDate) >= serviceRefreshInterval

        async let sampledSystem = Task.detached(priority: .utility) {
            Self.captureSystemSample(at: now)
        }.value
        async let sampledIdentity = Task.detached(priority: .utility) {
            shouldCaptureIdentity ? Self.captureIdentity() : nil
        }.value
        async let sampledExtensions = Task.detached(priority: .utility) {
            shouldRefreshExtensions ? Self.captureExtensionStats() : nil
        }.value
        async let sampledIOServiceCount = Task.detached(priority: .utility) {
            shouldRefreshServices ? Self.captureIOServiceCount() : nil
        }.value

        let systemSample = await sampledSystem
        if let identity = await sampledIdentity {
            cachedIdentity = identity
        }

        if let extensionStats = await sampledExtensions {
            cachedExtensionStats = extensionStats
            extensionStatsDate = now
        }

        if let ioServiceCount = await sampledIOServiceCount {
            cachedIOServiceCount = ioServiceCount
            ioServiceCountDate = now
        }

        let cpu = Self.cpuUsage(current: systemSample.cpuTicks, previous: previousSystemSample?.cpuTicks)
        let rates = Self.vmRates(current: systemSample, previous: previousSystemSample)
        previousSystemSample = systemSample

        let identity = cachedIdentity ?? .unavailable
        let uptime = identity.bootDate.map { max(now.timeIntervalSince($0), 0) } ?? 0

        return KernelSnapshot(
            identity: identity,
            capturedAt: now,
            uptimeSeconds: uptime,
            totalCPUPercent: cpu.total,
            kernelCPUPercent: cpu.system,
            userCPUPercent: cpu.user,
            idleCPUPercent: cpu.idle,
            loadAverages: systemSample.loadAverages,
            processCount: systemSample.processCount,
            threadCount: systemSample.threadCount,
            wiredMemoryBytes: systemSample.wiredMemoryBytes,
            anonymousMemoryBytes: systemSample.anonymousMemoryBytes,
            compressedMemoryBytes: systemSample.compressedMemoryBytes,
            driverImageMemoryBytes: cachedExtensionStats.imageMemoryBytes,
            driverWiredMemoryBytes: cachedExtensionStats.wiredMemoryBytes,
            loadedExtensionCount: cachedExtensionStats.loadedCount,
            startedExtensionCount: cachedExtensionStats.startedCount,
            thirdPartyExtensionCount: cachedExtensionStats.thirdPartyCount,
            ioServiceCount: cachedIOServiceCount,
            pageFaultsPerSecond: rates.faults,
            pageInsPerSecond: rates.pageIns,
            compressionsPerSecond: rates.compressions,
            decompressionsPerSecond: rates.decompressions,
            memoryPressure: systemSample.memoryPressure
        )
    }

    private static func captureIdentity() -> KernelIdentity {
        let kernelVersion = sysctlString("kern.version")
        return KernelIdentity(
            release: sysctlString("kern.osrelease") ?? "--",
            osBuild: sysctlString("kern.osversion") ?? "--",
            xnuBuild: KernelIdentity.xnuBuild(from: kernelVersion) ?? "--",
            architecture: sysctlString("hw.machine") ?? "--",
            hostname: sysctlString("kern.hostname") ?? ProcessInfo.processInfo.hostName,
            logicalCoreCount: Int(sysctlInteger("hw.logicalcpu") ?? UInt64(ProcessInfo.processInfo.processorCount)),
            physicalCoreCount: Int(sysctlInteger("hw.physicalcpu") ?? UInt64(ProcessInfo.processInfo.processorCount)),
            pageSizeBytes: sysctlInteger("hw.pagesize") ?? UInt64(getpagesize()),
            maximumProcesses: sysctlInteger("kern.maxproc") ?? 0,
            maximumOpenFiles: sysctlInteger("kern.maxfiles") ?? 0,
            bootDate: systemBootDate()
        )
    }

    private static func captureSystemSample(at date: Date) -> KernelSystemSample {
        let vm = virtualMemorySample()
        let tasks = taskCounts()
        var loadAverages = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loadAverages, Int32(loadAverages.count))

        return KernelSystemSample(
            date: date,
            cpuTicks: systemCPUTicks(),
            loadAverages: loadAverages,
            processCount: tasks.processes,
            threadCount: tasks.threads,
            wiredMemoryBytes: vm.wiredMemoryBytes,
            anonymousMemoryBytes: vm.anonymousMemoryBytes,
            compressedMemoryBytes: vm.compressedMemoryBytes,
            faults: vm.faults,
            pageIns: vm.pageIns,
            compressions: vm.compressions,
            decompressions: vm.decompressions,
            memoryPressure: memoryPressure()
        )
    }

    private static func systemCPUTicks() -> KernelCPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .zero }
        return KernelCPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func virtualMemorySample() -> KernelVMSample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .zero }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return .zero }
        let bytesPerPage = UInt64(pageSize)

        return KernelVMSample(
            wiredMemoryBytes: UInt64(stats.wire_count) * bytesPerPage,
            anonymousMemoryBytes: UInt64(stats.internal_page_count) * bytesPerPage,
            compressedMemoryBytes: UInt64(stats.compressor_page_count) * bytesPerPage,
            faults: stats.faults,
            pageIns: stats.pageins,
            compressions: stats.compressions,
            decompressions: stats.decompressions
        )
    }

    private static func taskCounts() -> (processes: Int, threads: Int) {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else { return (0, 0) }

        var pids = [pid_t](
            repeating: 0,
            count: Int(requiredBytes) / MemoryLayout<pid_t>.stride
        )
        let writtenBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard writtenBytes > 0 else { return (0, 0) }

        let count = min(Int(writtenBytes) / MemoryLayout<pid_t>.stride, pids.count)
        var processes = 0
        var threads = 0
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskinfo()
            let infoSize = MemoryLayout<proc_taskinfo>.stride
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: infoSize) { reboundPointer in
                    proc_pidinfo(pid, PROC_PIDTASKINFO, 0, reboundPointer, Int32(infoSize))
                }
            }

            guard result == infoSize else { continue }
            processes += 1
            threads += Int(info.pti_threadnum)
        }

        return (processes, threads)
    }

    private static func captureExtensionStats() -> KernelExtensionStats {
        guard let unmanagedInfo = KextManagerCopyLoadedKextInfo(nil, nil) else {
            return .empty
        }

        let info = unmanagedInfo.takeRetainedValue() as NSDictionary
        var startedCount = 0
        var thirdPartyCount = 0
        var imageMemoryBytes: UInt64 = 0
        var wiredMemoryBytes: UInt64 = 0

        for (key, value) in info {
            let identifier = key as? String ?? ""
            guard let details = value as? NSDictionary else { continue }

            if (details["OSBundleStarted"] as? NSNumber)?.boolValue == true {
                startedCount += 1
            }
            if !identifier.hasPrefix("com.apple.") {
                thirdPartyCount += 1
            }
            imageMemoryBytes += (details["OSBundleLoadSize"] as? NSNumber)?.uint64Value ?? 0
            wiredMemoryBytes += (details["OSBundleWiredSize"] as? NSNumber)?.uint64Value ?? 0
        }

        return KernelExtensionStats(
            loadedCount: info.count,
            startedCount: startedCount,
            thirdPartyCount: thirdPartyCount,
            imageMemoryBytes: imageMemoryBytes,
            wiredMemoryBytes: wiredMemoryBytes
        )
    }

    private static func captureIOServiceCount() -> Int {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOService"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var count = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            count += 1
            IOObjectRelease(service)
        }
        return count
    }

    private static func cpuUsage(
        current: KernelCPUTicks,
        previous: KernelCPUTicks?
    ) -> (total: Double, system: Double, user: Double, idle: Double) {
        guard let previous else { return (0, 0, 0, 100) }
        let user = delta(current.user, previous.user)
        let system = delta(current.system, previous.system)
        let idle = delta(current.idle, previous.idle)
        let nice = delta(current.nice, previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return (0, 0, 0, 100) }

        let scale = 100 / Double(total)
        let userPercent = Double(user + nice) * scale
        let systemPercent = Double(system) * scale
        let idlePercent = Double(idle) * scale
        return (
            min(max(userPercent + systemPercent, 0), 100),
            min(max(systemPercent, 0), 100),
            min(max(userPercent, 0), 100),
            min(max(idlePercent, 0), 100)
        )
    }

    private static func vmRates(
        current: KernelSystemSample,
        previous: KernelSystemSample?
    ) -> (faults: Double, pageIns: Double, compressions: Double, decompressions: Double) {
        guard let previous else { return (0, 0, 0, 0) }
        let elapsed = current.date.timeIntervalSince(previous.date)
        guard elapsed > 0 else { return (0, 0, 0, 0) }

        return (
            Double(delta(current.faults, previous.faults)) / elapsed,
            Double(delta(current.pageIns, previous.pageIns)) / elapsed,
            Double(delta(current.compressions, previous.compressions)) / elapsed,
            Double(delta(current.decompressions, previous.decompressions)) / elapsed
        )
    }

    private static func memoryPressure() -> KernelMemoryPressure {
        switch sysctlInteger("kern.memorystatus_vm_pressure_level") {
        case 1:
            .normal
        case 2:
            .warning
        case 4:
            .critical
        default:
            .unknown
        }
    }

    private static func systemBootDate() -> Date? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
    }

    private static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func sysctlInteger(_ key: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

private struct KernelSystemSample: Sendable {
    let date: Date
    let cpuTicks: KernelCPUTicks
    let loadAverages: [Double]
    let processCount: Int
    let threadCount: Int
    let wiredMemoryBytes: UInt64
    let anonymousMemoryBytes: UInt64
    let compressedMemoryBytes: UInt64
    let faults: UInt64
    let pageIns: UInt64
    let compressions: UInt64
    let decompressions: UInt64
    let memoryPressure: KernelMemoryPressure
}

private struct KernelCPUTicks: Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    static let zero = KernelCPUTicks(user: 0, system: 0, idle: 0, nice: 0)
}

private struct KernelVMSample: Sendable {
    let wiredMemoryBytes: UInt64
    let anonymousMemoryBytes: UInt64
    let compressedMemoryBytes: UInt64
    let faults: UInt64
    let pageIns: UInt64
    let compressions: UInt64
    let decompressions: UInt64

    static let zero = KernelVMSample(
        wiredMemoryBytes: 0,
        anonymousMemoryBytes: 0,
        compressedMemoryBytes: 0,
        faults: 0,
        pageIns: 0,
        compressions: 0,
        decompressions: 0
    )
}

private struct KernelExtensionStats: Sendable {
    let loadedCount: Int
    let startedCount: Int
    let thirdPartyCount: Int
    let imageMemoryBytes: UInt64
    let wiredMemoryBytes: UInt64

    static let empty = KernelExtensionStats(
        loadedCount: 0,
        startedCount: 0,
        thirdPartyCount: 0,
        imageMemoryBytes: 0,
        wiredMemoryBytes: 0
    )
}
