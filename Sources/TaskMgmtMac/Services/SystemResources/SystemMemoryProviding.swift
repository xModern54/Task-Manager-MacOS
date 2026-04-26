import Foundation

protocol SystemMemoryProviding: Sendable {
    func usage() -> SystemMemoryUsage
    func usagePercent() -> Int
}

struct SystemMemoryUsage: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let compressedBytes: UInt64

    var usagePercent: Int {
        guard totalBytes > 0 else { return 0 }
        let percentage = Double(usedBytes) / Double(totalBytes) * 100
        return min(max(Int(percentage.rounded()), 0), 100)
    }
}
