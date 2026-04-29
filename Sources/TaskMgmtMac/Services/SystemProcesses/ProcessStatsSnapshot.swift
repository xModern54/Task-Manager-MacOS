import Foundation

struct ProcessStatsSnapshot: Hashable, Sendable {
    let timestampNanoseconds: UInt64
    let activeProcessorCount: Int
    let cpuTimeNanoseconds: UInt64
    let userTimeNanoseconds: UInt64
    let systemTimeNanoseconds: UInt64
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let threadCount: Int
    let runningThreadCount: Int
    let priority: Int
    let policy: Int
    let niceValue: Int
    let openFileCount: Int
    let pageFaults: Int
    let pageIns: Int
    let copyOnWriteFaults: Int
    let machMessagesSent: Int
    let machMessagesReceived: Int
    let machSyscalls: Int
    let unixSyscalls: Int
    let contextSwitches: Int
}
