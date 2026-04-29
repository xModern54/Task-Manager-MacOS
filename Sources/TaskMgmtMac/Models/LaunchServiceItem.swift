import Foundation

struct LaunchServiceItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let domain: String
    let kind: LaunchServiceKind
    let status: LaunchServiceStatus
    let pid: Int32?
    let executablePath: String?
    let plistPath: String?
    let trigger: String
    let properties: [LaunchServiceProperty]
}

enum LaunchServiceKind: String, Hashable, Sendable {
    case launchAgent = "LaunchAgent"
    case launchDaemon = "LaunchDaemon"
}

enum LaunchServiceStatus: String, Hashable, Sendable {
    case running = "Running"
    case waiting = "Waiting"
    case offline = "Offline"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

struct LaunchServiceProperty: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let value: String
}
