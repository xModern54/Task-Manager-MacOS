import Foundation

struct KernelSnapshot: Sendable {
    let identity: KernelIdentity
    let capturedAt: Date
    let uptimeSeconds: TimeInterval
    let totalCPUPercent: Double
    let kernelCPUPercent: Double
    let userCPUPercent: Double
    let idleCPUPercent: Double
    let loadAverages: [Double]
    let processCount: Int
    let threadCount: Int
    let wiredMemoryBytes: UInt64
    let anonymousMemoryBytes: UInt64
    let compressedMemoryBytes: UInt64
    let driverImageMemoryBytes: UInt64
    let driverWiredMemoryBytes: UInt64
    let loadedExtensionCount: Int
    let startedExtensionCount: Int
    let thirdPartyExtensionCount: Int
    let ioServiceCount: Int
    let pageFaultsPerSecond: Double
    let pageInsPerSecond: Double
    let compressionsPerSecond: Double
    let decompressionsPerSecond: Double
    let memoryPressure: KernelMemoryPressure

    static let unavailable = KernelSnapshot(
        identity: .unavailable,
        capturedAt: .distantPast,
        uptimeSeconds: 0,
        totalCPUPercent: 0,
        kernelCPUPercent: 0,
        userCPUPercent: 0,
        idleCPUPercent: 0,
        loadAverages: [0, 0, 0],
        processCount: 0,
        threadCount: 0,
        wiredMemoryBytes: 0,
        anonymousMemoryBytes: 0,
        compressedMemoryBytes: 0,
        driverImageMemoryBytes: 0,
        driverWiredMemoryBytes: 0,
        loadedExtensionCount: 0,
        startedExtensionCount: 0,
        thirdPartyExtensionCount: 0,
        ioServiceCount: 0,
        pageFaultsPerSecond: 0,
        pageInsPerSecond: 0,
        compressionsPerSecond: 0,
        decompressionsPerSecond: 0,
        memoryPressure: .unknown
    )
}

struct KernelIdentity: Sendable {
    let release: String
    let osBuild: String
    let xnuBuild: String
    let architecture: String
    let hostname: String
    let logicalCoreCount: Int
    let physicalCoreCount: Int
    let pageSizeBytes: UInt64
    let maximumProcesses: UInt64
    let maximumOpenFiles: UInt64
    let bootDate: Date?

    static let unavailable = KernelIdentity(
        release: "--",
        osBuild: "--",
        xnuBuild: "--",
        architecture: "--",
        hostname: "--",
        logicalCoreCount: 0,
        physicalCoreCount: 0,
        pageSizeBytes: 0,
        maximumProcesses: 0,
        maximumOpenFiles: 0,
        bootDate: nil
    )

    static func xnuBuild(from kernelVersion: String?) -> String? {
        guard let kernelVersion,
              let rootRange = kernelVersion.range(of: "root:") else {
            return nil
        }

        let suffix = kernelVersion[rootRange.upperBound...]
        let build = suffix.split(separator: "/", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return build?.isEmpty == false ? build : nil
    }
}

enum KernelMemoryPressure: String, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
    case unknown = "Unknown"
}
