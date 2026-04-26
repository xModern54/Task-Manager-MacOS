import Foundation

protocol SystemGPUInfoProviding: Sendable {
    func snapshot() async -> SystemGPUSnapshot
}

struct SystemGPUSnapshot: Sendable {
    let name: String
    let usagePercent: Int
    let allocatedMemoryBytes: UInt64
    let inUseMemoryBytes: UInt64
    let hasUnifiedMemory: Bool
    let coreCount: Int?

    static let unavailable = SystemGPUSnapshot(
        name: "GPU",
        usagePercent: 0,
        allocatedMemoryBytes: 0,
        inUseMemoryBytes: 0,
        hasUnifiedMemory: false,
        coreCount: nil
    )
}
