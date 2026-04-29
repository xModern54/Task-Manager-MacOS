import Foundation

struct StartupItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let publisher: String
    let status: StartupItemStatus
    let runtime: StartupRuntimeSnapshot
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

struct StartupRuntimeSnapshot: Hashable, Sendable {
    let state: StartupRuntimeState
    let pid: Int32?
    let detail: String?

    static let unknown = StartupRuntimeSnapshot(state: .unknown, pid: nil, detail: nil)

    var displayText: String {
        switch state {
        case .running, .appRunning:
            "Running"
        case .idle, .notLoaded, .disabled, .unknown:
            state.rawValue
        }
    }
}

enum StartupRuntimeState: String, Hashable, Sendable {
    case running = "Running"
    case appRunning = "App running"
    case idle = "Idle"
    case notLoaded = "Not loaded"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

enum StartupItemStatus: String, Hashable, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case unknown = "Unknown"
}

enum StartupItemSource: String, Hashable, Sendable {
    case backgroundItem = "Background item"
    case launchAgent = "Launch agent"
    case launchDaemon = "Launch daemon"
    case loginItem = "Login item"
}
