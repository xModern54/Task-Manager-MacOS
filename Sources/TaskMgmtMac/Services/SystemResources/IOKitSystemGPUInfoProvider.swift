import Foundation
import IOKit
import Metal

actor IOKitSystemGPUInfoProvider: SystemGPUInfoProviding {
    private var cachedDetails = SystemGPUSnapshot.unavailable

    func snapshot(includeDetails: Bool) async -> SystemGPUSnapshot {
        let registrySnapshot = Self.ioRegistrySnapshot(includeDetails: includeDetails)

        guard includeDetails else {
            let deviceName = cachedDetails.name == SystemGPUSnapshot.unavailable.name
                ? MTLCreateSystemDefaultDevice()?.name ?? cachedDetails.name
                : cachedDetails.name

            return SystemGPUSnapshot(
                name: deviceName,
                usagePercent: registrySnapshot.usagePercent,
                allocatedMemoryBytes: cachedDetails.allocatedMemoryBytes,
                inUseMemoryBytes: cachedDetails.inUseMemoryBytes,
                hasUnifiedMemory: cachedDetails.hasUnifiedMemory,
                coreCount: cachedDetails.coreCount
            )
        }

        let device = MTLCreateSystemDefaultDevice()
        let snapshot = SystemGPUSnapshot(
            name: device?.name ?? registrySnapshot.name ?? cachedDetails.name,
            usagePercent: registrySnapshot.usagePercent,
            allocatedMemoryBytes: registrySnapshot.allocatedMemoryBytes,
            inUseMemoryBytes: registrySnapshot.inUseMemoryBytes,
            hasUnifiedMemory: device?.hasUnifiedMemory ?? cachedDetails.hasUnifiedMemory,
            coreCount: registrySnapshot.coreCount ?? cachedDetails.coreCount
        )

        cachedDetails = snapshot
        return snapshot
    }

    private struct RegistrySnapshot {
        let name: String?
        let usagePercent: Int
        let allocatedMemoryBytes: UInt64
        let inUseMemoryBytes: UInt64
        let coreCount: Int?
    }

    private static func ioRegistrySnapshot(includeDetails: Bool) -> RegistrySnapshot {
        var iterator: io_iterator_t = 0
        let result = IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return RegistrySnapshot(name: nil, usagePercent: 0, allocatedMemoryBytes: 0, inUseMemoryBytes: 0, coreCount: nil)
        }

        defer {
            IOObjectRelease(iterator)
        }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer {
                IOObjectRelease(entry)
            }

            guard isGPUAccelerator(entry) else {
                continue
            }

            guard let statistics = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            return RegistrySnapshot(
                name: includeDetails ? stringProperty("IONameMatched", from: entry) : nil,
                usagePercent: clampedPercent(statistics["Device Utilization %"]),
                allocatedMemoryBytes: includeDetails ? numericValue(statistics["Alloc system memory"]) ?? 0 : 0,
                inUseMemoryBytes: includeDetails ? numericValue(statistics["In use system memory"]) ?? 0 : 0,
                coreCount: includeDetails ? numericValue(
                    IORegistryEntryCreateCFProperty(
                        entry,
                        "gpu-core-count" as CFString,
                        kCFAllocatorDefault,
                        0
                    )?.takeRetainedValue()
                ).map(Int.init) : nil
            )
        }

        return RegistrySnapshot(name: nil, usagePercent: 0, allocatedMemoryBytes: 0, inUseMemoryBytes: 0, coreCount: nil)
    }

    private static func isGPUAccelerator(_ entry: io_registry_entry_t) -> Bool {
        var classNameBuffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &classNameBuffer)
        let classNameBytes = classNameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let className = String(decoding: classNameBytes, as: UTF8.self)

        return className.localizedCaseInsensitiveContains("AGXAccelerator")
            || className.localizedCaseInsensitiveContains("IOGraphicsAccelerator")
    }

    private static func stringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }

    private static func clampedPercent(_ value: Any?) -> Int {
        guard let percent = numericValue(value) else { return 0 }
        return min(max(Int(percent), 0), 100)
    }

    private static func numericValue(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            number.uint64Value
        case let value as UInt64:
            value
        case let value as UInt:
            UInt64(value)
        case let value as Int:
            value >= 0 ? UInt64(value) : nil
        default:
            nil
        }
    }
}
