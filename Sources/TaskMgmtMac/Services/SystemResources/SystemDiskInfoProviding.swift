import Foundation

protocol SystemDiskInfoProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemDiskSnapshot
}

struct SystemDiskSnapshot: Sendable {
    let name: String
    let type: String
    let activePercent: Int
    let readBytesPerSecond: UInt64
    let writeBytesPerSecond: UInt64
    let averageResponseMilliseconds: Double
    let capacityBytes: UInt64
    let freeBytes: UInt64

    var usedBytes: UInt64 {
        capacityBytes > freeBytes ? capacityBytes - freeBytes : 0
    }

    static let unavailable = SystemDiskSnapshot(
        name: "MacBook Internal SSD",
        type: "SSD",
        activePercent: 0,
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0,
        averageResponseMilliseconds: 0,
        capacityBytes: 0,
        freeBytes: 0
    )
}
