import Darwin
import Foundation

struct LaunchctlServiceProvider: LaunchServiceProviding {
    func services() async -> [LaunchServiceItem] {
        await Task.detached(priority: .utility) {
            readLaunchServices()
        }.value
    }
}

private func readLaunchServices() -> [LaunchServiceItem] {
    let user = LaunchServiceConsoleUser.current
    let guiDomain = "gui/\(user.uid)"
    let domainSnapshots = [
        guiDomain: launchctlDomainSnapshot(guiDomain),
        "system": launchctlDomainSnapshot("system")
    ]
    let disabledSnapshots = [
        guiDomain: launchctlDisabledLabels(in: guiDomain),
        "system": launchctlDisabledLabels(in: "system")
    ]

    return launchServicePlistSources(user: user)
        .compactMap { source in
            launchServiceItem(
                source: source,
                domainSnapshots: domainSnapshots,
                disabledSnapshots: disabledSnapshots
            )
        }
        .sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusRank(lhs.status) < statusRank(rhs.status)
            }

            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
}

private struct LaunchServicePlistSource {
    let path: String
    let domain: String
    let kind: LaunchServiceKind
}

private struct LaunchctlServiceRuntime {
    let pid: Int32?
    let lastExitStatus: String?
}

private struct LaunchServiceConsoleUser {
    let uid: Int
    let homeDirectory: String

    static var current: LaunchServiceConsoleUser {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
           let ownerID = attributes[.ownerAccountID] as? NSNumber {
            let uid = uid_t(ownerID.uint32Value)
            if uid != 0,
               let password = getpwuid(uid),
               let home = password.pointee.pw_dir {
                return LaunchServiceConsoleUser(uid: Int(uid), homeDirectory: String(cString: home))
            }
        }

        let uid = getuid()
        let home = getpwuid(uid).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
        return LaunchServiceConsoleUser(uid: Int(uid), homeDirectory: home ?? NSHomeDirectory())
    }
}

private func launchServicePlistSources(user: LaunchServiceConsoleUser) -> [LaunchServicePlistSource] {
    let guiDomain = "gui/\(user.uid)"
    let sourceDirectories: [(String, String, LaunchServiceKind)] = [
        ("\(user.homeDirectory)/Library/LaunchAgents", guiDomain, .launchAgent),
        ("/Library/LaunchAgents", guiDomain, .launchAgent),
        ("/System/Library/LaunchAgents", guiDomain, .launchAgent),
        ("/Library/LaunchDaemons", "system", .launchDaemon),
        ("/System/Library/LaunchDaemons", "system", .launchDaemon)
    ]

    return sourceDirectories.flatMap { directory, domain, kind in
        launchServicePlistPaths(in: directory).map { path in
            LaunchServicePlistSource(path: path, domain: domain, kind: kind)
        }
    }
}

private func launchServicePlistPaths(in directory: String) -> [String] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
        return []
    }

    return contents
        .filter { $0.hasSuffix(".plist") }
        .map { URL(fileURLWithPath: directory).appendingPathComponent($0).path }
}

private func launchServiceItem(
    source: LaunchServicePlistSource,
    domainSnapshots: [String: [String: LaunchctlServiceRuntime]],
    disabledSnapshots: [String: [String: Bool]]
) -> LaunchServiceItem? {
    guard let plist = NSDictionary(contentsOfFile: source.path) as? [String: Any] else {
        return nil
    }

    let label = plist["Label"] as? String ?? URL(fileURLWithPath: source.path).deletingPathExtension().lastPathComponent
    let executablePath = executablePath(from: plist)
    let disabledLabels = disabledSnapshots[source.domain] ?? [:]
    let runtime = domainSnapshots[source.domain]?[label]
    let status = launchServiceStatus(label: label, plist: plist, runtime: runtime, disabledLabels: disabledLabels)
    let trigger = triggerDescription(from: plist)

    return LaunchServiceItem(
        id: "\(source.domain)/\(label)",
        label: label,
        domain: source.domain,
        kind: source.kind,
        status: status,
        pid: runtime?.pid,
        executablePath: executablePath,
        plistPath: source.path,
        trigger: trigger,
        properties: launchServiceProperties(
            label: label,
            source: source,
            plist: plist,
            status: status,
            runtime: runtime,
            executablePath: executablePath,
            trigger: trigger
        )
    )
}

private func launchServiceStatus(
    label: String,
    plist: [String: Any],
    runtime: LaunchctlServiceRuntime?,
    disabledLabels: [String: Bool]
) -> LaunchServiceStatus {
    if let isEnabled = disabledLabels[label], !isEnabled {
        return .disabled
    }

    if let disabled = plist["Disabled"] as? Bool, disabled {
        return .disabled
    }

    guard let runtime else {
        return .offline
    }

    if runtime.pid != nil {
        return .running
    }

    return .waiting
}

private func statusRank(_ status: LaunchServiceStatus) -> Int {
    switch status {
    case .running:
        0
    case .waiting:
        1
    case .offline:
        2
    case .disabled:
        3
    case .unknown:
        4
    }
}

private func launchctlDomainSnapshot(_ domain: String) -> [String: LaunchctlServiceRuntime] {
    let output = runLaunchctl(arguments: ["print", domain])
    guard output.status == 0 else { return [:] }
    return parseLaunchctlServices(output.output)
}

private func parseLaunchctlServices(_ output: String) -> [String: LaunchctlServiceRuntime] {
    var runtimes: [String: LaunchctlServiceRuntime] = [:]
    var isInsideServices = false

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "services = {" {
            isInsideServices = true
            continue
        }

        if isInsideServices, trimmed == "}" {
            break
        }

        guard isInsideServices else { continue }

        let fields = trimmed.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 3,
              let pidValue = Int32(fields[0]) else {
            continue
        }

        let statusText = String(fields[1])
        let label = fields.dropFirst(2).joined(separator: " ")
        let pid = pidValue > 0 ? pidValue : nil
        let lastExitStatus = statusText == "-" ? nil : statusText
        runtimes[label] = LaunchctlServiceRuntime(pid: pid, lastExitStatus: lastExitStatus)
    }

    return runtimes
}

private func launchctlDisabledLabels(in domain: String) -> [String: Bool] {
    let output = runLaunchctl(arguments: ["print-disabled", domain])
    guard output.status == 0 else { return [:] }

    var labels: [String: Bool] = [:]
    for line in output.output.components(separatedBy: .newlines) {
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

private func runLaunchctl(arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    } catch {
        return (1, error.localizedDescription)
    }
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

private func triggerDescription(from plist: [String: Any]) -> String {
    if plist["KeepAlive"] != nil {
        return "KeepAlive"
    }

    if boolValue(plist["RunAtLoad"]) == true {
        return "Run at load"
    }

    if plist["MachServices"] != nil {
        return "Mach service"
    }

    if plist["Sockets"] != nil {
        return "Socket"
    }

    if plist["LaunchEvents"] != nil {
        return "Launch event"
    }

    if plist["StartInterval"] != nil || plist["StartCalendarInterval"] != nil {
        return "Schedule"
    }

    return "On demand"
}

private func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
        return value
    }

    if let value = value as? NSNumber {
        return value.boolValue
    }

    return nil
}

private func launchServiceProperties(
    label: String,
    source: LaunchServicePlistSource,
    plist: [String: Any],
    status: LaunchServiceStatus,
    runtime: LaunchctlServiceRuntime?,
    executablePath: String?,
    trigger: String
) -> [LaunchServiceProperty] {
    var properties: [LaunchServiceProperty] = []

    appendProperty("label", "Label", label, to: &properties)
    appendProperty("status", "Status", status.rawValue, to: &properties)
    appendProperty("pid", "PID", runtime?.pid.map(String.init), to: &properties)
    appendProperty("lastExit", "Last exit status", runtime?.lastExitStatus, to: &properties)
    appendProperty("domain", "Domain", source.domain, to: &properties)
    appendProperty("kind", "Type", source.kind.rawValue, to: &properties)
    appendProperty("trigger", "Trigger", trigger, to: &properties)
    appendProperty("plist", "Plist path", source.path, to: &properties)
    appendProperty("executable", "Executable", executablePath, to: &properties)
    appendProperty("runAtLoad", "Run at load", plistBoolText(plist["RunAtLoad"]), to: &properties)
    appendProperty("disabled", "Disabled", plistBoolText(plist["Disabled"]), to: &properties)
    appendProperty("keepAlive", "KeepAlive", plistValueText(plist["KeepAlive"]), to: &properties)
    appendProperty("processType", "Process type", plistValueText(plist["ProcessType"] ?? plist["POSIXSpawnType"]), to: &properties)
    appendProperty("user", "User", plistValueText(plist["UserName"]), to: &properties)
    appendProperty("group", "Group", plistValueText(plist["GroupName"]), to: &properties)
    appendProperty("mach", "Mach services", plistValueText(plist["MachServices"]), to: &properties)
    appendProperty("sockets", "Sockets", plistValueText(plist["Sockets"]), to: &properties)
    appendProperty("events", "Launch events", plistValueText(plist["LaunchEvents"]), to: &properties)
    appendProperty("startInterval", "Start interval", plistValueText(plist["StartInterval"]), to: &properties)
    appendProperty("startCalendar", "Start calendar", plistValueText(plist["StartCalendarInterval"]), to: &properties)
    appendProperty("arguments", "Program arguments", plistValueText(plist["ProgramArguments"]), to: &properties)

    return properties
}

private func appendProperty(
    _ id: String,
    _ name: String,
    _ value: String?,
    to properties: inout [LaunchServiceProperty]
) {
    guard let value, !value.isEmpty else { return }
    properties.append(LaunchServiceProperty(id: id, name: name, value: value))
}

private func plistBoolText(_ value: Any?) -> String? {
    guard let bool = boolValue(value) else { return nil }
    return bool ? "Yes" : "No"
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
