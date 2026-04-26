import Darwin
import Foundation
import IOKit

actor IOKitSystemDiskInfoProvider: SystemDiskInfoProviding {
    private var previousStats: BlockStorageStats?
    private var cachedDetails = SystemDiskSnapshot.unavailable

    func snapshot(includeDetails: Bool) async -> SystemDiskSnapshot {
        let sample = await Task.detached(priority: .utility) {
            DiskSample(
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                stats: Self.blockStorageStats(),
                details: includeDetails ? Self.diskDetails() : nil
            )
        }.value

        let liveMetrics = liveMetrics(from: sample)
        previousStats = sample.stats

        if let details = sample.details {
            cachedDetails = SystemDiskSnapshot(
                name: details.name,
                type: details.type,
                activePercent: liveMetrics.activePercent,
                readBytesPerSecond: liveMetrics.readBytesPerSecond,
                writeBytesPerSecond: liveMetrics.writeBytesPerSecond,
                averageResponseMilliseconds: liveMetrics.averageResponseMilliseconds,
                capacityBytes: details.capacityBytes,
                freeBytes: details.freeBytes
            )

            return cachedDetails
        }

        return SystemDiskSnapshot(
            name: cachedDetails.name,
            type: cachedDetails.type,
            activePercent: liveMetrics.activePercent,
            readBytesPerSecond: liveMetrics.readBytesPerSecond,
            writeBytesPerSecond: liveMetrics.writeBytesPerSecond,
            averageResponseMilliseconds: liveMetrics.averageResponseMilliseconds,
            capacityBytes: cachedDetails.capacityBytes,
            freeBytes: cachedDetails.freeBytes
        )
    }

    private func liveMetrics(from sample: DiskSample) -> DiskLiveMetrics {
        guard let current = sample.stats else {
            return DiskLiveMetrics.empty
        }

        guard let previousStats else {
            return DiskLiveMetrics.empty
        }

        let elapsedSeconds = max(Double(current.timestampNanoseconds - previousStats.timestampNanoseconds) / 1_000_000_000, 0)
        guard elapsedSeconds > 0 else {
            return DiskLiveMetrics.empty
        }

        let readBytes = delta(current.readBytes, previousStats.readBytes)
        let writeBytes = delta(current.writeBytes, previousStats.writeBytes)
        let operations = delta(current.totalOperations, previousStats.totalOperations)
        let activeTimeNanoseconds = delta(current.totalTimeNanoseconds, previousStats.totalTimeNanoseconds)
        let activePercent = min(max(Int((Double(activeTimeNanoseconds) / (elapsedSeconds * 1_000_000_000) * 100).rounded()), 0), 100)
        let responseMilliseconds = operations > 0
            ? Double(activeTimeNanoseconds) / Double(operations) / 1_000_000
            : 0

        return DiskLiveMetrics(
            activePercent: activePercent,
            readBytesPerSecond: UInt64(Double(readBytes) / elapsedSeconds),
            writeBytesPerSecond: UInt64(Double(writeBytes) / elapsedSeconds),
            averageResponseMilliseconds: responseMilliseconds
        )
    }

    private static func blockStorageStats() -> BlockStorageStats? {
        var iterator: io_iterator_t = 0
        let result = IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer {
                IOObjectRelease(entry)
            }

            guard className(for: entry).localizedCaseInsensitiveContains("IOBlockStorageDriver"),
                  let statistics = IORegistryEntryCreateCFProperty(
                    entry,
                    "Statistics" as CFString,
                    kCFAllocatorDefault,
                    0
                  )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            return BlockStorageStats(
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
                readBytes: numericValue(statistics["Bytes (Read)"]) ?? 0,
                writeBytes: numericValue(statistics["Bytes (Write)"]) ?? 0,
                readOperations: numericValue(statistics["Operations (Read)"]) ?? 0,
                writeOperations: numericValue(statistics["Operations (Write)"]) ?? 0,
                readTimeNanoseconds: numericValue(statistics["Total Time (Read)"]) ?? 0,
                writeTimeNanoseconds: numericValue(statistics["Total Time (Write)"]) ?? 0
            )
        }

        return nil
    }

    private static func diskDetails() -> DiskDetails {
        let deviceInfo = storageDeviceInfo()
        let volume = volumeInfo()

        return DiskDetails(
            name: deviceInfo?.name ?? "MacBook Internal SSD",
            type: deviceInfo?.type == "Solid State" ? "SSD" : deviceInfo?.type ?? "SSD",
            capacityBytes: volume.capacityBytes,
            freeBytes: volume.freeBytes
        )
    }

    private static func storageDeviceInfo() -> StorageDeviceInfo? {
        var iterator: io_iterator_t = 0
        let result = IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer {
                IOObjectRelease(entry)
            }

            guard let characteristics = IORegistryEntryCreateCFProperty(
                entry,
                "Device Characteristics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
                  let productName = characteristics["Product Name"] as? String,
                  let mediumType = characteristics["Medium Type"] as? String else {
                continue
            }

            return StorageDeviceInfo(name: productName, type: mediumType)
        }

        return nil
    }

    private static func volumeInfo() -> VolumeInfo {
        var stats = statfs()

        guard "/".withCString({ statfs($0, &stats) }) == 0 else {
            return VolumeInfo(capacityBytes: 0, freeBytes: 0)
        }

        let blockSize = UInt64(stats.f_bsize)
        return VolumeInfo(
            capacityBytes: UInt64(stats.f_blocks) * blockSize,
            freeBytes: UInt64(stats.f_bavail) * blockSize
        )
    }

    private static func className(for entry: io_registry_entry_t) -> String {
        var classNameBuffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &classNameBuffer)
        let classNameBytes = classNameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: classNameBytes, as: UTF8.self)
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

    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

private struct DiskSample: Sendable {
    let timestampNanoseconds: UInt64
    let stats: BlockStorageStats?
    let details: DiskDetails?
}

private struct BlockStorageStats: Sendable {
    let timestampNanoseconds: UInt64
    let readBytes: UInt64
    let writeBytes: UInt64
    let readOperations: UInt64
    let writeOperations: UInt64
    let readTimeNanoseconds: UInt64
    let writeTimeNanoseconds: UInt64

    var totalOperations: UInt64 {
        readOperations + writeOperations
    }

    var totalTimeNanoseconds: UInt64 {
        readTimeNanoseconds + writeTimeNanoseconds
    }
}

private struct DiskLiveMetrics: Sendable {
    let activePercent: Int
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64
    let averageResponseMilliseconds: Double

    static let empty = DiskLiveMetrics(
        activePercent: 0,
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0,
        averageResponseMilliseconds: 0
    )
}

private struct DiskDetails: Sendable {
    let name: String
    let type: String
    let capacityBytes: UInt64
    let freeBytes: UInt64
}

private struct StorageDeviceInfo: Sendable {
    let name: String
    let type: String
}

private struct VolumeInfo: Sendable {
    let capacityBytes: UInt64
    let freeBytes: UInt64
}
