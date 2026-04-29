import Darwin
import Foundation

struct SystemEventsLoginItemProvider: StartupItemProviding {
    func startupItems() async -> [StartupItem] {
        await Task.detached(priority: .utility) {
            readLoginItems()
        }.value
    }
}

private func readLoginItems() -> [StartupItem] {
    let result = runLoginItemsScript()
    guard result.status == 0 else { return [] }

    return result.output
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { parseLoginItemLine(String($0)) }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
}

private func runLoginItemsScript() -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", loginItemsAppleScript]

    if RootLaunchManager.isRunningAsRoot, let consoleUser = ConsoleUser.current {
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "asuser",
            "\(consoleUser.uid)",
            "/usr/bin/sudo",
            "-u",
            consoleUser.name,
            "/usr/bin/osascript",
            "-e",
            loginItemsAppleScript
        ]
    }

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    } catch {
        return (1, "")
    }
}

private func parseLoginItemLine(_ line: String) -> StartupItem? {
    let fields = line.components(separatedBy: "\t")
    guard fields.count >= 4 else { return nil }

    let name = fields[0]
    let path = fields[1].isEmpty ? nil : fields[1]
    let hidden = fields[2] == "true"
    let publisher = publisher(for: path)

    return StartupItem(
        id: path ?? "\(StartupItemSource.loginItem.rawValue)-\(name)",
        name: name,
        publisher: publisher,
        status: .enabled,
        impact: .notMeasured,
        source: .loginItem,
        path: path,
        isHidden: hidden
    )
}

private func publisher(for path: String?) -> String {
    guard let path else { return "Unknown" }
    let bundle = Bundle(path: path)

    if let bundleIdentifier = bundle?.bundleIdentifier, !bundleIdentifier.isEmpty {
        return bundleIdentifier
    }

    if path.hasPrefix("/Applications/") {
        return "User application"
    }

    if path.hasPrefix("/System/") {
        return "Apple"
    }

    return "Unknown"
}

private struct ConsoleUser {
    let uid: uid_t
    let name: String

    static var current: ConsoleUser? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
              let ownerID = attributes[.ownerAccountID] as? NSNumber else {
            return nil
        }

        let uid = uid_t(ownerID.uint32Value)
        guard uid != 0 else { return nil }
        guard let password = getpwuid(uid),
              let name = password.pointee.pw_name else {
            return nil
        }

        return ConsoleUser(uid: uid, name: String(cString: name))
    }
}

private let loginItemsAppleScript = """
set outputLines to {}
tell application "System Events"
    repeat with itemRef in every login item
        set itemName to ""
        set itemPath to ""
        set itemHidden to false
        set itemKind to ""
        try
            set itemName to name of itemRef
        end try
        try
            set itemPath to path of itemRef
        end try
        try
            set itemHidden to hidden of itemRef
        end try
        try
            set itemKind to kind of itemRef
        end try
        set end of outputLines to itemName & tab & itemPath & tab & (itemHidden as text) & tab & itemKind
    end repeat
end tell
set AppleScript's text item delimiters to linefeed
return outputLines as text
"""
