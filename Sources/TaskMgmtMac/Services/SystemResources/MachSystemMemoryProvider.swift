import Darwin
import Foundation

struct MachSystemMemoryProvider: SystemMemoryProviding {
    func usage() -> SystemMemoryUsage {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return .empty
        }

        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return .empty
        }

        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let fileBacked = UInt64(stats.external_page_count)
        let speculative = UInt64(stats.speculative_count)
        let purgeable = UInt64(stats.purgeable_count)
        let used = active + wired + compressed
        guard total > 0 else {
            return .empty
        }
        let usedBytes = used * pageSize
        let cachedBytes = (fileBacked + speculative + purgeable) * pageSize
        let swapUsage = Self.swapUsage()

        return SystemMemoryUsage(
            totalBytes: total,
            usedBytes: min(usedBytes, total),
            compressedBytes: compressed * pageSize,
            cachedBytes: cachedBytes,
            wiredBytes: wired * pageSize,
            swapUsedBytes: swapUsage.usedBytes,
            swapTotalBytes: swapUsage.totalBytes
        )
    }

    func usagePercent() -> Int {
        usage().usagePercent
    }

    private static func swapUsage() -> (usedBytes: UInt64, totalBytes: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride

        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            return (0, 0)
        }

        return (usage.xsu_used, usage.xsu_total)
    }
}

private extension SystemMemoryUsage {
    static let empty = SystemMemoryUsage(
        totalBytes: 0,
        usedBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        wiredBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0
    )
}
