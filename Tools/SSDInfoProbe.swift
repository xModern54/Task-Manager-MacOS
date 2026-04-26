import Darwin
import Foundation
import IOKit

struct VolumeSnapshot {
    let mountPoint: String
    let capacityBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 {
        capacityBytes > freeBytes ? capacityBytes - freeBytes : 0
    }
}

struct BlockStorageStats {
    let className: String
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

struct StorageDeviceInfo {
    let productName: String
    let mediumType: String
    let revision: String
    let serialNumber: String
}

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(bytes))
}

func formatRate(_ bytes: UInt64, elapsedSeconds: Double) -> String {
    guard elapsedSeconds > 0 else { return "0 KB/s" }
    return "\(formatBytes(UInt64(Double(bytes) / elapsedSeconds)))/s"
}

func numericValue(_ value: Any?) -> UInt64? {
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

func className(for entry: io_registry_entry_t) -> String {
    var classNameBuffer = [CChar](repeating: 0, count: 128)
    IOObjectGetClass(entry, &classNameBuffer)
    let classNameBytes = classNameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: classNameBytes, as: UTF8.self)
}

func volumeSnapshot(mountPoint: String = "/") -> VolumeSnapshot? {
    var stats = statfs()

    guard mountPoint.withCString({ statfs($0, &stats) }) == 0 else {
        return nil
    }

    let blockSize = UInt64(stats.f_bsize)
    let capacity = UInt64(stats.f_blocks) * blockSize
    let free = UInt64(stats.f_bavail) * blockSize

    return VolumeSnapshot(
        mountPoint: mountPoint,
        capacityBytes: capacity,
        freeBytes: free
    )
}

func blockStorageStats() -> [BlockStorageStats] {
    var iterator: io_iterator_t = 0
    let result = IORegistryCreateIterator(
        kIOMainPortDefault,
        kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively),
        &iterator
    )

    guard result == KERN_SUCCESS else {
        return []
    }

    defer {
        IOObjectRelease(iterator)
    }

    var snapshots: [BlockStorageStats] = []

    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer {
            IOObjectRelease(entry)
        }

        let entryClassName = className(for: entry)
        guard entryClassName.localizedCaseInsensitiveContains("IOBlockStorageDriver") else {
            continue
        }

        guard let statistics = IORegistryEntryCreateCFProperty(
            entry,
            "Statistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            continue
        }

        snapshots.append(
            BlockStorageStats(
                className: entryClassName,
                readBytes: numericValue(statistics["Bytes (Read)"]) ?? 0,
                writeBytes: numericValue(statistics["Bytes (Write)"]) ?? 0,
                readOperations: numericValue(statistics["Operations (Read)"]) ?? 0,
                writeOperations: numericValue(statistics["Operations (Write)"]) ?? 0,
                readTimeNanoseconds: numericValue(statistics["Total Time (Read)"]) ?? 0,
                writeTimeNanoseconds: numericValue(statistics["Total Time (Write)"]) ?? 0
            )
        )
    }

    return snapshots
}

func storageDeviceInfo() -> StorageDeviceInfo? {
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
        )?.takeRetainedValue() as? [String: Any] else {
            continue
        }

        guard let productName = characteristics["Product Name"] as? String,
              let mediumType = characteristics["Medium Type"] as? String else {
            continue
        }

        return StorageDeviceInfo(
            productName: productName,
            mediumType: mediumType,
            revision: characteristics["Product Revision Level"] as? String ?? "--",
            serialNumber: characteristics["Serial Number"] as? String ?? "--"
        )
    }

    return nil
}

func delta(_ end: UInt64, _ start: UInt64) -> UInt64 {
    end >= start ? end - start : 0
}

print("Device")
if let deviceInfo = storageDeviceInfo() {
    print("  product: \(deviceInfo.productName)")
    print("  medium type: \(deviceInfo.mediumType)")
    print("  revision: \(deviceInfo.revision)")
    print("  serial: \(deviceInfo.serialNumber)")
} else {
    print("  failed to find Device Characteristics in IORegistry")
}

print("")
print("Volume")
if let volume = volumeSnapshot() {
    print("  mount: \(volume.mountPoint)")
    print("  capacity: \(formatBytes(volume.capacityBytes)) (\(volume.capacityBytes) bytes)")
    print("  used: \(formatBytes(volume.usedBytes)) (\(volume.usedBytes) bytes)")
    print("  free: \(formatBytes(volume.freeBytes)) (\(volume.freeBytes) bytes)")
} else {
    print("  failed to read / with statfs")
}

let firstStats = blockStorageStats()
print("")
print("Block storage devices with statistics: \(firstStats.count)")
for stats in firstStats {
    print("  \(stats.className)")
    print("    lifetime read: \(formatBytes(stats.readBytes))")
    print("    lifetime written: \(formatBytes(stats.writeBytes))")
    print("    read operations: \(stats.readOperations)")
    print("    write operations: \(stats.writeOperations)")
}

let sampleInterval = 1.0
Thread.sleep(forTimeInterval: sampleInterval)

let secondStats = blockStorageStats()
guard let before = firstStats.first, let after = secondStats.first else {
    exit(0)
}

let readDelta = delta(after.readBytes, before.readBytes)
let writeDelta = delta(after.writeBytes, before.writeBytes)
let operationDelta = delta(after.totalOperations, before.totalOperations)
let timeDelta = delta(after.totalTimeNanoseconds, before.totalTimeNanoseconds)
let activePercent = min(max(Double(timeDelta) / (sampleInterval * 1_000_000_000) * 100, 0), 100)
let averageResponseMilliseconds = operationDelta > 0
    ? Double(timeDelta) / Double(operationDelta) / 1_000_000
    : 0

print("")
print("One-second live sample")
print("  active time estimate: \(String(format: "%.1f", activePercent))%")
print("  average response time: \(String(format: "%.3f", averageResponseMilliseconds)) ms")
print("  read speed: \(formatRate(readDelta, elapsedSeconds: sampleInterval))")
print("  write speed: \(formatRate(writeDelta, elapsedSeconds: sampleInterval))")
