import Foundation

struct SystemProcessInfo: Hashable, Sendable {
    let pid: Int
    let name: String
    let executablePath: String?
    let cpuTimeNanoseconds: UInt64
    let residentMemoryBytes: UInt64
    let physicalFootprintBytes: UInt64
}
