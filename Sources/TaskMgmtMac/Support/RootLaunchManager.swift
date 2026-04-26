import AppKit
import Foundation

enum RootLaunchManager {
    static let probeArgument = "--taskmgmt-root-launch-probe"

    static var isRunningAsRoot: Bool {
        geteuid() == 0
    }

    static var executablePath: String {
        let url = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return url.resolvingSymlinksInPath().path
    }

    static func exitIfHandlingProbeArgument() {
        guard CommandLine.arguments.contains(probeArgument) else { return }
        exit(isRunningAsRoot ? 0 : 1)
    }

    static func canRelaunchWithoutPassword() async -> Bool {
        await runAndWait(
            launchPath: "/usr/bin/sudo",
            arguments: ["-n", executablePath, probeArgument]
        ) == 0
    }

    static func relaunchAsRoot() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", executablePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func installRootLaunchRule() async throws {
        let username = NSUserName()
        let rulePath = "/etc/sudoers.d/taskmgmtmac-root-launch"
        let sudoersRule = """
        # Allows TaskMgmtMac to relaunch itself as root without storing an administrator password.
        \(sudoersEscape(username)) ALL=(root) NOPASSWD: \(sudoersEscape(executablePath))
        """

        let script = """
        set -e
        tmp="$(/usr/bin/mktemp /tmp/taskmgmtmac-sudoers.XXXXXX)"
        /bin/cat > "$tmp" <<'TASKMGMT_SUDOERS_EOF'
        \(sudoersRule)
        TASKMGMT_SUDOERS_EOF
        /usr/sbin/chown root:wheel "$tmp"
        /bin/chmod 440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        /bin/mv "$tmp" "\(shellEscape(rulePath))"
        """

        let appleScript = """
        do shell script "\(appleScriptEscape(script))" with administrator privileges
        """

        let status = await runAndWait(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )

        guard status == 0 else {
            throw RootLaunchError.installFailed
        }
    }

    static func terminateCurrentProcess() {
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    private static func runAndWait(launchPath: String, arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: 1)
                }
            }
        }
    }

    private static func shellEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func sudoersEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: " ", with: "\\ ")
            .replacingOccurrences(of: "\t", with: "\\\t")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
    }
}

enum RootLaunchError: LocalizedError {
    case installFailed
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .installFailed:
            "Could not install the root launch rule."
        case .relaunchFailed:
            "Could not relaunch TaskMgmtMac as root."
        }
    }
}
