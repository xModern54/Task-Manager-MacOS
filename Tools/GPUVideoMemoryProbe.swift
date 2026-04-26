import Foundation
import IOKit
import Metal

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(bytes))
}

func printDevice(_ device: any MTLDevice, prefix: String = "") {
    print("\(prefix)name: \(device.name)")
    print("\(prefix)registryID: \(device.registryID)")
    print("\(prefix)hasUnifiedMemory: \(device.hasUnifiedMemory)")
    print("\(prefix)isLowPower: \(device.isLowPower)")
    print("\(prefix)isRemovable: \(device.isRemovable)")
    print("\(prefix)isHeadless: \(device.isHeadless)")
    print("\(prefix)recommendedMaxWorkingSetSize: \(formatBytes(device.recommendedMaxWorkingSetSize)) (\(device.recommendedMaxWorkingSetSize) bytes)")
    print("\(prefix)currentAllocatedSize: \(formatBytes(UInt64(device.currentAllocatedSize))) (\(device.currentAllocatedSize) bytes)")
}

struct IORegistryGPUMemorySnapshot {
    let className: String
    let statistics: [String: UInt64]
}

func numericValue(_ value: Any) -> UInt64? {
    switch value {
    case let number as NSNumber:
        return number.uint64Value
    case let value as UInt64:
        return value
    case let value as UInt:
        return UInt64(value)
    case let value as Int:
        return value >= 0 ? UInt64(value) : nil
    default:
        return nil
    }
}

func gpuMemorySnapshotsFromIORegistry() -> [IORegistryGPUMemorySnapshot] {
    var iterator: io_iterator_t = 0
    let result = IORegistryCreateIterator(
        kIOMainPortDefault,
        kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively),
        &iterator
    )

    guard result == KERN_SUCCESS else {
        print("IORegistryCreateIterator failed: \(result)")
        return []
    }

    defer {
        IOObjectRelease(iterator)
    }

    var snapshots: [IORegistryGPUMemorySnapshot] = []

    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer {
            IOObjectRelease(entry)
        }

        var classNameBuffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &classNameBuffer)
        let className = String(cString: classNameBuffer)

        guard className.localizedCaseInsensitiveContains("AGXAccelerator")
            || className.localizedCaseInsensitiveContains("IOGraphicsAccelerator") else {
            continue
        }

        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            continue
        }

        let memoryStatistics = property.reduce(into: [String: UInt64]()) { result, element in
            let key = element.key
            guard key.localizedCaseInsensitiveContains("memory"),
                  let value = numericValue(element.value) else {
                return
            }

            result[key] = value
        }

        if !memoryStatistics.isEmpty {
            snapshots.append(IORegistryGPUMemorySnapshot(className: className, statistics: memoryStatistics))
        }
    }

    return snapshots
}

func printIORegistryGPUMemorySnapshots(_ title: String) {
    print("")
    print(title)

    let snapshots = gpuMemorySnapshotsFromIORegistry()

    if snapshots.isEmpty {
        print("  no GPU memory statistics found in IORegistry")
        return
    }

    for snapshot in snapshots {
        print("  \(snapshot.className)")

        for key in snapshot.statistics.keys.sorted() {
            if let value = snapshot.statistics[key] {
                print("    \(key): \(formatBytes(value)) (\(value) bytes)")
            }
        }
    }
}

let devices = MTLCopyAllDevices()
print("Metal devices: \(devices.count)")

for (index, device) in devices.enumerated() {
    print("")
    print("Device \(index)")
    printDevice(device, prefix: "  ")
}

guard let device = MTLCreateSystemDefaultDevice() else {
    print("No default Metal device")
    exit(1)
}

print("")
print("Default device allocation check")
printDevice(device, prefix: "  before ")
printIORegistryGPUMemorySnapshots("IORegistry GPU memory before allocation")

let allocationSize = 256 * 1024 * 1024
let buffer = device.makeBuffer(length: allocationSize, options: .storageModeShared)

if buffer == nil {
    print("  failed to allocate \(formatBytes(UInt64(allocationSize))) test buffer")
    exit(2)
}

print("  allocated test buffer: \(formatBytes(UInt64(allocationSize)))")
printDevice(device, prefix: "  after  ")
Thread.sleep(forTimeInterval: 0.5)
printIORegistryGPUMemorySnapshots("IORegistry GPU memory after allocation")

withExtendedLifetime(buffer) {
    Thread.sleep(forTimeInterval: 1.0)
}
