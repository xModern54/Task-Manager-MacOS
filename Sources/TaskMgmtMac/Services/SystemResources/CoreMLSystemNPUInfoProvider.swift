import CoreML
import Foundation
import IOKit

actor CoreMLSystemNPUInfoProvider: SystemNPUInfoProviding {
    private var cachedSnapshot = SystemNPUSnapshot.unavailable
    private var didLoadLightweightInfo = false
    private var didLoadDetailedInfo = false

    func snapshot(includeDetails: Bool) async -> SystemNPUSnapshot {
        if !didLoadLightweightInfo {
            cachedSnapshot = Self.coreMLSnapshot()
            didLoadLightweightInfo = true
        }

        guard includeDetails else {
            return cachedSnapshot
        }

        if !didLoadDetailedInfo {
            cachedSnapshot = Self.mergedSnapshot(coreMLSnapshot: cachedSnapshot, registryInfo: Self.aneRegistryInfo())
            didLoadDetailedInfo = true
        }

        return cachedSnapshot
    }

    private struct ANERegistryInfo {
        let registryClassName: String
        let matchedName: String
        let architecture: String
        let coreCount: Int?
        let version: Int?
        let minorVersion: Int?
        let boardType: Int?
    }

    private static func coreMLSnapshot() -> SystemNPUSnapshot {
        var coreCount: Int?
        var foundNeuralEngine = false

        for device in MLComputeDevice.allComputeDevices {
            if case .neuralEngine(let neuralEngine) = device {
                coreCount = neuralEngine.totalCoreCount
                foundNeuralEngine = true
                break
            }
        }

        return SystemNPUSnapshot(
            name: "Apple Neural Engine",
            usagePercent: nil,
            coreCount: coreCount,
            architecture: "--",
            version: "--",
            boardType: "--",
            registryClassName: "--",
            matchedName: "--",
            computeDeviceState: foundNeuralEngine ? "Available" : "Unavailable",
            precisionSupport: "Core ML managed"
        )
    }

    private static func mergedSnapshot(
        coreMLSnapshot: SystemNPUSnapshot,
        registryInfo: ANERegistryInfo?
    ) -> SystemNPUSnapshot {
        guard let registryInfo else {
            return coreMLSnapshot
        }

        let versionText: String
        if let version = registryInfo.version, let minorVersion = registryInfo.minorVersion {
            versionText = "\(version).\(minorVersion)"
        } else if let version = registryInfo.version {
            versionText = "\(version)"
        } else {
            versionText = "--"
        }

        return SystemNPUSnapshot(
            name: coreMLSnapshot.name,
            usagePercent: coreMLSnapshot.usagePercent,
            coreCount: coreMLSnapshot.coreCount ?? registryInfo.coreCount,
            architecture: registryInfo.architecture,
            version: versionText,
            boardType: registryInfo.boardType.map(String.init) ?? "--",
            registryClassName: registryInfo.registryClassName,
            matchedName: registryInfo.matchedName,
            computeDeviceState: coreMLSnapshot.computeDeviceState,
            precisionSupport: coreMLSnapshot.precisionSupport
        )
    }

    private static func aneRegistryInfo() -> ANERegistryInfo? {
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

            return ANERegistryInfo(
                registryClassName: entryClassName,
                matchedName: stringProperty("IONameMatched", from: entry) ?? "--",
                architecture: properties["ANEDevicePropertyTypeANEArchitectureTypeStr"] as? String ?? "--",
                coreCount: numericValue(properties["ANEDevicePropertyNumANECores"]),
                version: numericValue(properties["ANEDevicePropertyANEVersion"]),
                minorVersion: numericValue(properties["ANEDevicePropertyANEMinorVersion"]),
                boardType: numericValue(properties["ANEDevicePropertyANEHWBoardType"])
            )
        }

        return nil
    }

    private static func className(for entry: io_registry_entry_t) -> String {
        var classNameBuffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &classNameBuffer)
        let classNameBytes = classNameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: classNameBytes, as: UTF8.self)
    }

    private static func stringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }

    private static func numericValue(_ value: Any?) -> Int? {
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
}
