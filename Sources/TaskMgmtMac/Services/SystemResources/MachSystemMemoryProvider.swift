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
            return SystemMemoryUsage(totalBytes: 0, usedBytes: 0, compressedBytes: 0)
        }

        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return SystemMemoryUsage(totalBytes: 0, usedBytes: 0, compressedBytes: 0)
        }

        let pageSize = UInt64(hostPageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = active + wired + compressed
        guard total > 0 else {
            return SystemMemoryUsage(totalBytes: 0, usedBytes: 0, compressedBytes: 0)
        }
        let usedBytes = used * pageSize

        return SystemMemoryUsage(
            totalBytes: total,
            usedBytes: min(usedBytes, total),
            compressedBytes: compressed * pageSize
        )
    }

    func usagePercent() -> Int {
        usage().usagePercent
    }
}
