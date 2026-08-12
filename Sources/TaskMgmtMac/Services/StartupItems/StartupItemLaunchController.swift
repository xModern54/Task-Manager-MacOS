import Foundation

struct StartupItemLaunchController: Sendable {
    func setEnabled(_ enabled: Bool, item: StartupItem) async -> StartupItemLaunchControlResult {
        var failures: [String] = []

        for target in item.controlTargets {
            if target.domain == "system" {
                do {
                    try await PrivilegedHelperClient.shared.setLaunchItemEnabled(enabled, target: target.id)
                } catch {
                    failures.append("\(target.id): \(error.localizedDescription)")
                }
            } else {
                let result = await Task.detached(priority: .userInitiated) {
                    runLaunchctl(enabled: enabled, target: target)
                }.value

                if result.status != 0 {
                    failures.append("\(target.id): \(result.output)")
                }
            }
        }

        if failures.isEmpty {
            return StartupItemLaunchControlResult(success: true, message: nil)
        }

        return StartupItemLaunchControlResult(success: false, message: failures.joined(separator: "\n"))
    }
}

struct StartupItemLaunchControlResult: Sendable {
    let success: Bool
    let message: String?
}

private func runLaunchctl(enabled: Bool, target: StartupItemControlTarget) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = [
        enabled ? "enable" : "disable",
        target.id
    ]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
        return (1, error.localizedDescription)
    }
}
