import Foundation

enum LaunchServiceClipboardInfoBuilder {
    static func text(for service: LaunchServiceItem, processRow: ProcessTableRow?) -> String {
        let copiedAt = ISO8601DateFormatter().string(from: Date())
        let executableName = service.executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        let searchTerms = [
            service.label,
            executableName,
            "macOS launchd"
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        var lines: [String] = [
            "TaskMgmtMac launchd service diagnostic context",
            "",
            "Suggested question:",
            "What is this macOS launchd service or agent, what software does it belong to, is it expected, and is it safe to disable, unload, or remove it?",
            "",
            "Search query:",
            searchTerms,
            "",
            "Captured:",
            copiedAt,
            "",
            "Launchd identity:",
            "Label: \(service.label)",
            "Domain: \(service.domain)",
            "Type: \(service.kind.rawValue)",
            "Status: \(service.status.rawValue)",
            "PID: \(service.pid.map(String.init) ?? "Unavailable")",
            "Trigger: \(service.trigger)",
            "Plist path: \(service.plistPath ?? "Unavailable")",
            "Executable path: \(service.executablePath ?? "Unavailable")",
            "",
            "Launchd properties:"
        ]

        if service.properties.isEmpty {
            lines.append("Unavailable")
        } else {
            lines.append(contentsOf: service.properties.map { "\($0.name): \($0.value)" })
        }

        lines.append(contentsOf: [
            "",
            "Related process:"
        ])

        if let processRow {
            lines.append(ProcessClipboardInfoBuilder.text(for: processRow))
        } else if service.pid == nil {
            lines.append("No live PID is currently associated with this launchd item.")
        } else {
            lines.append("A PID is listed, but TaskMgmtMac could not build a process context for it.")
        }

        lines.append(contentsOf: [
            "",
            "Privacy note:",
            "Environment variables are intentionally not included because they can contain tokens, secrets, and private paths."
        ])

        return lines.joined(separator: "\n")
    }
}
