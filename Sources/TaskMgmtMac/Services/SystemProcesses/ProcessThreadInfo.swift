import Foundation

struct ProcessThreadInfo: Identifiable, Hashable, Sendable {
    let threadID: UInt64
    let name: String?
    let cpuPercent: Double
    let state: ProcessThreadState
    let currentPriority: Int
    let basePriority: Int
    let maxPriority: Int
    let policy: Int
    let sleepTimeSeconds: Int
    let userTimeNanoseconds: UInt64
    let systemTimeNanoseconds: UInt64

    var id: UInt64 { threadID }

    var displayName: String {
        guard let name, !name.isEmpty else {
            return "Thread \(threadID)"
        }

        return name
    }
}

enum ProcessThreadState: String, Hashable, Sendable {
    case running = "Running"
    case stopped = "Stopped"
    case waiting = "Waiting"
    case uninterruptible = "Uninterruptible"
    case halted = "Halted"
    case unknown = "Unknown"
}
