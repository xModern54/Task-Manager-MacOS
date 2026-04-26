import CoreML
import Foundation
import IOKit

struct ANEDeviceProperties {
    let registryClassName: String
    let matchedName: String
    let architecture: String
    let coreCount: Int?
    let version: Int?
    let minorVersion: Int?
    let boardType: Int?
}

func className(for entry: io_registry_entry_t) -> String {
    var classNameBuffer = [CChar](repeating: 0, count: 128)
    IOObjectGetClass(entry, &classNameBuffer)
    let classNameBytes = classNameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: classNameBytes, as: UTF8.self)
}

func numericValue(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
        number.intValue
    case let value as Int:
        value
    case let value as UInt64:
        Int(value)
    case let value as UInt:
        Int(value)
    default:
        nil
    }
}

func stringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
    IORegistryEntryCreateCFProperty(
        entry,
        key as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue() as? String
}

func aneDeviceProperties() -> [ANEDeviceProperties] {
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

    var devices: [ANEDeviceProperties] = []

    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer {
            IOObjectRelease(entry)
        }

        let entryClassName = className(for: entry)
        guard entryClassName.localizedCaseInsensitiveContains("ANE") else {
            continue
        }

        guard let properties = IORegistryEntryCreateCFProperty(
            entry,
            "DeviceProperties" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            continue
        }

        devices.append(
            ANEDeviceProperties(
                registryClassName: entryClassName,
                matchedName: stringProperty("IONameMatched", from: entry) ?? "--",
                architecture: properties["ANEDevicePropertyTypeANEArchitectureTypeStr"] as? String ?? "--",
                coreCount: numericValue(properties["ANEDevicePropertyNumANECores"]),
                version: numericValue(properties["ANEDevicePropertyANEVersion"]),
                minorVersion: numericValue(properties["ANEDevicePropertyANEMinorVersion"]),
                boardType: numericValue(properties["ANEDevicePropertyANEHWBoardType"])
            )
        )
    }

    return devices
}

print("Core ML compute devices")
if #available(macOS 14.0, *) {
    for device in MLComputeDevice.allComputeDevices {
        switch device {
        case .cpu(let cpu):
            print("  CPU: \(cpu.description)")
        case .gpu(let gpu):
            print("  GPU: \(gpu.description)")
        case .neuralEngine(let neuralEngine):
            print("  Neural Engine: \(neuralEngine.description)")
            print("    totalCoreCount: \(neuralEngine.totalCoreCount)")
        @unknown default:
            print("  Unknown compute device: \(device)")
        }
    }
} else {
    print("  MLComputeDevice.allComputeDevices requires macOS 14+")
}

print("")
print("IORegistry ANE devices")
let aneDevices = aneDeviceProperties()
if aneDevices.isEmpty {
    print("  no ANE DeviceProperties found")
} else {
    for device in aneDevices {
        print("  \(device.registryClassName)")
        print("    matched: \(device.matchedName)")
        print("    architecture: \(device.architecture)")
        print("    cores: \(device.coreCount.map(String.init) ?? "--")")
        print("    version: \(device.version.map(String.init) ?? "--").\(device.minorVersion.map(String.init) ?? "--")")
        print("    boardType: \(device.boardType.map(String.init) ?? "--")")
    }
}
