import Foundation

struct StartupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let publisher: String
    let status: StartupItemStatus
    let impact: StartupImpact
    let source: StartupItemSource
    let path: String?
    let detail: String?
    let isHidden: Bool
    let controlTargets: [StartupItemControlTarget]
    let properties: [StartupItemProperty]

    var isControllable: Bool {
        !controlTargets.isEmpty
    }
}

struct StartupItemControlTarget: Identifiable, Hashable, Sendable {
    var id: String { "\(domain)/\(label)" }

    let label: String
    let domain: String
    let plistPath: String?
    let executablePath: String?
}

struct StartupItemProperty: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let value: String
}

enum StartupItemStatus: String, Hashable, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

enum StartupImpact: String, Hashable, Sendable {
    case notMeasured = "Not measured"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

enum StartupItemSource: String, Hashable, Sendable {
    case backgroundItem = "Background item"
    case launchAgent = "Launch agent"
    case launchDaemon = "Launch daemon"
    case loginItem = "Login item"
}
