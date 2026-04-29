import Darwin
import Foundation

struct LaunchAgentPlistStartupItemProvider: StartupItemProviding {
    func startupItems() async -> [StartupItem] {
        await Task.detached(priority: .utility) {
            readLaunchAgentItems()
        }.value
    }
}

private func readLaunchAgentItems() -> [StartupItem] {
    guard let user = LaunchAgentConsoleUser.current else { return [] }

    let directories = [
        "\(user.homeDirectory)/Library/LaunchAgents",
        "/Library/LaunchAgents"
    ]
    let disabledLabels = launchctlDisabledLabels(in: "gui/\(user.uid)")
    let runtimeResolver = StartupRuntimeResolver()

    return directories
        .flatMap { launchAgentPlistPaths(in: $0) }
        .compactMap { path in
            startupItem(
                fromPlistAt: path,
                user: user,
                disabledLabels: disabledLabels,
                runtimeResolver: runtimeResolver
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
}

private func launchAgentPlistPaths(in directory: String) -> [String] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
        return []
    }

    return contents
        .filter { $0.hasSuffix(".plist") }
        .map { URL(fileURLWithPath: directory).appendingPathComponent($0).path }
        .sorted()
}

private func startupItem(
    fromPlistAt path: String,
    user: LaunchAgentConsoleUser,
    disabledLabels: [String: Bool],
    runtimeResolver: StartupRuntimeResolver
) -> StartupItem? {
    guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any] else {
        return nil
    }

    let label = plist["Label"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let executablePath = executablePath(from: plist)
    let target = StartupItemControlTarget(
        label: label,
        domain: "gui/\(user.uid)",
        plistPath: path,
        executablePath: executablePath
    )
    let status = startupStatus(label: label, plist: plist, disabledLabels: disabledLabels)
    let bundleIdentifier = bundleIdentifier(forExecutablePath: executablePath)
    let runtime = runtimeResolver.runtime(for: StartupRuntimeRecord(
        status: status,
        bundleIdentifier: bundleIdentifier,
        path: executablePath,
        controlTargets: [target]
    ))
    let publisher = publisher(bundleIdentifier: bundleIdentifier, executablePath: executablePath)

    return StartupItem(
        id: path,
        name: displayName(label: label, executablePath: executablePath),
        publisher: publisher,
        status: status,
        runtime: runtime,
        source: .launchAgent,
        path: path,
        detail: path,
        isHidden: false,
        controlTargets: [target],
        properties: properties(
            label: label,
            path: path,
            plist: plist,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            publisher: publisher,
            status: status,
            runtime: runtime,
            target: target
        )
    )
}

private func startupStatus(
    label: String,
    plist: [String: Any],
    disabledLabels: [String: Bool]
) -> StartupItemStatus {
    if let isEnabled = disabledLabels[label] {
        return isEnabled ? .enabled : .disabled
    }

    if let isDisabled = plist["Disabled"] as? Bool, isDisabled {
        return .disabled
    }

    return .enabled
}

private func launchctlDisabledLabels(in domain: String) -> [String: Bool] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print-disabled", domain]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseLaunchctlDisabledOutput(output)
    } catch {
        return [:]
    }
}

private func parseLaunchctlDisabledOutput(_ output: String) -> [String: Bool] {
    var labels: [String: Bool] = [:]

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""),
              let endQuote = trimmed.dropFirst().firstIndex(of: "\"") else {
            continue
        }

        let label = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote])
        if trimmed.contains("=> enabled") {
            labels[label] = true
        } else if trimmed.contains("=> disabled") {
            labels[label] = false
        }
    }

    return labels
}

private func executablePath(from plist: [String: Any]) -> String? {
    if let program = plist["Program"] as? String, !program.isEmpty {
        return program
    }

    guard let arguments = plist["ProgramArguments"] as? [String],
          let executable = arguments.first,
          !executable.isEmpty else {
        return nil
    }

    return executable
}

private func displayName(label: String, executablePath: String?) -> String {
    if let executablePath {
        return URL(fileURLWithPath: executablePath).lastPathComponent
    }

    return label
}

private func publisher(bundleIdentifier: String?, executablePath: String?) -> String {
    if let bundleIdentifier {
        return bundleIdentifier
    }

    guard let executablePath else { return "Unknown" }

    if executablePath.hasPrefix("/opt/homebrew/") {
        return "Homebrew"
    }

    if executablePath.hasPrefix("/Applications/") {
        return "User application"
    }

    return "Unknown"
}

private func bundleIdentifier(forExecutablePath executablePath: String?) -> String? {
    guard let executablePath,
          let appURL = appBundleURL(forExecutablePath: executablePath),
          let bundle = Bundle(url: appURL) else {
        return nil
    }

    return bundle.bundleIdentifier
}

private func appBundleURL(forExecutablePath path: String) -> URL? {
    var url = URL(fileURLWithPath: path)

    while url.path != "/" {
        if url.pathExtension == "app" {
            return url
        }

        url.deleteLastPathComponent()
    }

    return nil
}

private func properties(
    label: String,
    path: String,
    plist: [String: Any],
    executablePath: String?,
    bundleIdentifier: String?,
    publisher: String,
    status: StartupItemStatus,
    runtime: StartupRuntimeSnapshot,
    target: StartupItemControlTarget
) -> [StartupItemProperty] {
    var properties: [StartupItemProperty] = []

    appendProperty("label", "Label", label, to: &properties)
    appendProperty("publisher", "Publisher", publisher, to: &properties)
    appendProperty("status", "Status", status.rawValue, to: &properties)
    appendProperty("runtime", "Runtime", runtime.displayText, to: &properties)
    appendProperty("runtimePID", "Runtime PID", runtime.pid.map(String.init), to: &properties)
    appendProperty("runtimeDetail", "Runtime detail", runtime.detail, to: &properties)
    appendProperty("source", "Source", StartupItemSource.launchAgent.rawValue, to: &properties)
    appendProperty("plist", "Plist path", path, to: &properties)
    appendProperty("executable", "Executable path", executablePath, to: &properties)
    appendProperty("bundle", "Bundle identifier", bundleIdentifier, to: &properties)
    appendProperty("target", "Launchd target", target.id, to: &properties)
    appendProperty("runAtLoad", "Run at load", boolText(plist["RunAtLoad"]), to: &properties)
    appendProperty("disabled", "Disabled key", boolText(plist["Disabled"]), to: &properties)
    appendProperty("keepAlive", "Keep alive", plistValueText(plist["KeepAlive"]), to: &properties)
    appendProperty("startInterval", "Start interval", plistValueText(plist["StartInterval"]), to: &properties)
    appendProperty("startCalendar", "Start calendar interval", plistValueText(plist["StartCalendarInterval"]), to: &properties)
    appendProperty("machServices", "Mach services", plistValueText(plist["MachServices"]), to: &properties)
    appendProperty("programArguments", "Program arguments", plistValueText(plist["ProgramArguments"]), to: &properties)

    return properties
}

private func appendProperty(
    _ id: String,
    _ name: String,
    _ value: String?,
    to properties: inout [StartupItemProperty]
) {
    guard let value, !value.isEmpty else { return }
    properties.append(StartupItemProperty(id: id, name: name, value: value))
}

private func boolText(_ value: Any?) -> String? {
    guard let value = value as? Bool else { return nil }
    return value ? "Yes" : "No"
}

private func plistValueText(_ value: Any?) -> String? {
    guard let value else { return nil }

    if let string = value as? String {
        return string
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    if let array = value as? [Any] {
        return array.map { String(describing: $0) }.joined(separator: " ")
    }

    if let dictionary = value as? [String: Any] {
        return dictionary
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
    }

    return String(describing: value)
}

private struct LaunchAgentConsoleUser {
    let uid: Int
    let homeDirectory: String

    static var current: LaunchAgentConsoleUser? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
              let ownerID = attributes[.ownerAccountID] as? NSNumber else {
            return fallback
        }

        let uid = uid_t(ownerID.uint32Value)
        guard uid != 0,
              let password = getpwuid(uid),
              let home = password.pointee.pw_dir else {
            return fallback
        }

        return LaunchAgentConsoleUser(uid: Int(uid), homeDirectory: String(cString: home))
    }

    private static var fallback: LaunchAgentConsoleUser? {
        let uid = getuid()
        guard let password = getpwuid(uid),
              let home = password.pointee.pw_dir else {
            return nil
        }

        return LaunchAgentConsoleUser(uid: Int(uid), homeDirectory: String(cString: home))
    }
}
