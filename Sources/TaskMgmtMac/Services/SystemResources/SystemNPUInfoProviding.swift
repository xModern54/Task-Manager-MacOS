import Foundation

protocol SystemNPUInfoProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemNPUSnapshot
}

struct SystemNPUSnapshot: Sendable {
    let name: String
    let usagePercent: Int?
    let coreCount: Int?
    let architecture: String
    let version: String
    let boardType: String
    let registryClassName: String
    let matchedName: String
    let computeDeviceState: String
    let precisionSupport: String

    static let unavailable = SystemNPUSnapshot(
        name: "Neural Engine",
        usagePercent: nil,
        coreCount: nil,
        architecture: "--",
        version: "--",
        boardType: "--",
        registryClassName: "--",
        matchedName: "--",
        computeDeviceState: "--",
        precisionSupport: "Core ML managed"
    )
}
