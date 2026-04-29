import Foundation

struct StartupRuntimeResolver: Sendable {
    private let processPathsByPID: [Int32: String]

    init() {
        processPathsByPID = readProcessPaths()
    }

    func runtime(for item: StartupItem) -> StartupRuntimeSnapshot {
        if !item.controlTargets.isEmpty {
            return adjustedRuntime(launchdRuntime(for: item.controlTargets), status: item.status)
        }

        if let pid = pidForItemPath(item.path) {
            return StartupRuntimeSnapshot(
                state: .appRunning,
                pid: pid,
                detail: "Matched by executable path. This proves the app is running, but not that launchd started it."
            )
        }

        if item.status == .disabled {
            return StartupRuntimeSnapshot(state: .disabled, pid: nil, detail: "The startup item is disabled.")
        }

        return StartupRuntimeSnapshot(state: .idle, pid: nil, detail: "No matching running process was found.")
    }

    func runtime(for record: StartupRuntimeRecord) -> StartupRuntimeSnapshot {
        if !record.controlTargets.isEmpty {
            return adjustedRuntime(launchdRuntime(for: record.controlTargets), status: record.status)
        }

        if let pid = pidForBundleIdentifier(record.bundleIdentifier) {
            return StartupRuntimeSnapshot(
                state: .appRunning,
                pid: pid,
                detail: "Matched by bundle identifier. This proves the app is running, but not that autostart launched it."
            )
        }

        if let pid = pidForItemPath(record.path) {
            return StartupRuntimeSnapshot(
                state: .appRunning,
                pid: pid,
                detail: "Matched by executable path. This proves the app is running, but not that autostart launched it."
            )
        }

        if record.status == .disabled {
            return StartupRuntimeSnapshot(state: .disabled, pid: nil, detail: "The startup item is disabled.")
        }

        if record.status == .enabled {
            return StartupRuntimeSnapshot(state: .idle, pid: nil, detail: "Enabled, but no active process is currently matched.")
        }

        return .unknown
    }

    private func adjustedRuntime(
        _ runtime: StartupRuntimeSnapshot,
        status: StartupItemStatus
    ) -> StartupRuntimeSnapshot {
        guard status == .disabled, runtime.state != .running else {
            return runtime
        }

        return StartupRuntimeSnapshot(state: .disabled, pid: nil, detail: "The startup item is disabled.")
    }

    private func launchdRuntime(for targets: [StartupItemControlTarget]) -> StartupRuntimeSnapshot {
        var sawNotLoaded = false
        var sawLoaded = false

        for target in targets {
            let result = runLaunchctlPrint(target)

            if result.status != 0 {
                if result.output.localizedCaseInsensitiveContains("Could not find service") {
                    sawNotLoaded = true
                }
                continue
            }

            sawLoaded = true

            if let pid = parseLaunchctlPID(result.output) {
                return StartupRuntimeSnapshot(
                    state: .running,
                    pid: pid,
                    detail: "Matched by launchd target \(target.id)."
                )
            }
        }

        if sawLoaded {
            return StartupRuntimeSnapshot(state: .idle, pid: nil, detail: "The launchd service is loaded but has no active PID.")
        }

        if sawNotLoaded {
            return StartupRuntimeSnapshot(state: .notLoaded, pid: nil, detail: "launchctl does not currently have this service loaded.")
        }

        return .unknown
    }

    private func pidForBundleIdentifier(_ bundleIdentifier: String?) -> Int32? {
        guard let bundleIdentifier else { return nil }

        for path in processPathsByPID.values {
            guard let bundleURL = bundleURL(forExecutablePath: path),
                  let bundle = Bundle(url: bundleURL),
                  bundle.bundleIdentifier == bundleIdentifier else {
                continue
            }

            return processPathsByPID.first { $0.value == path }?.key
        }

        return nil
    }

    private func pidForItemPath(_ path: String?) -> Int32? {
        guard let executablePath = executablePath(forItemPath: path) else { return nil }

        return processPathsByPID.first { _, processPath in
            processPath == executablePath
        }?.key
    }
}

struct StartupRuntimeRecord: Sendable {
    let status: StartupItemStatus
    let bundleIdentifier: String?
    let path: String?
    let controlTargets: [StartupItemControlTarget]
}

private func readProcessPaths() -> [Int32: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["axo", "pid=,comm="]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parsePSOutput(output)
    } catch {
        return [:]
    }
}

private func parsePSOutput(_ output: String) -> [Int32: String] {
    var pathsByPID: [Int32: String] = [:]

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpace = trimmed.firstIndex(where: \.isWhitespace) else { continue }

        let pidText = String(trimmed[..<firstSpace])
        let path = String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespaces)

        guard let pid = Int32(pidText), !path.isEmpty else { continue }
        pathsByPID[pid] = path
    }

    return pathsByPID
}

private func runLaunchctlPrint(_ target: StartupItemControlTarget) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", target.id]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
        try process.run()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return (process.terminationStatus, output)
    } catch {
        return (1, error.localizedDescription)
    }
}

private func parseLaunchctlPID(_ output: String) -> Int32? {
    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("pid =") else { continue }

        let pidText = trimmed
            .dropFirst("pid =".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let pid = Int32(pidText) {
            return pid
        }
    }

    return nil
}

private func executablePath(forItemPath path: String?) -> String? {
    guard let path else { return nil }

    if path.hasSuffix(".app") {
        let infoPath = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist").path
        guard let info = NSDictionary(contentsOfFile: infoPath),
              let executableName = info["CFBundleExecutable"] as? String else {
            return nil
        }

        return URL(fileURLWithPath: path)
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName)
            .path
    }

    return path
}

private func bundleURL(forExecutablePath path: String) -> URL? {
    var url = URL(fileURLWithPath: path)

    while url.path != "/" {
        if url.pathExtension == "app" {
            return url
        }

        url.deleteLastPathComponent()
    }

    return nil
}
