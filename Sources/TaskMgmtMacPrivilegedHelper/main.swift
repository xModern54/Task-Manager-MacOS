import Darwin
import Foundation
import PrivilegedHelperIPC
import Security

private final class PrivilegedHelperService: NSObject, PrivilegedHelperXPCProtocol {
    private let allowedLabelCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))

    func helperVersion(reply: @escaping (String) -> Void) {
        reply("1")
    }

    func collectPowerMetrics(reply: @escaping (String?, String?) -> Void) {
        let result = Self.runProcess(
            executable: "/usr/bin/powermetrics",
            arguments: [
                "-n", "1",
                "-i", "1000",
                "--samplers", "cpu_power,gpu_power,ane_power,thermal",
                "--show-pstates",
                "--show-extra-power-info"
            ],
            timeout: 10
        )
        reply(result.status == 0 ? result.output : nil, result.status == 0 ? nil : result.message)
    }

    func terminateProcess(_ pid: Int32, reply: @escaping (Bool, String?) -> Void) {
        guard pid > 1, pid != getpid() else {
            reply(false, "Refusing to terminate a protected process identifier.")
            return
        }

        guard kill(pid_t(pid), SIGTERM) == 0 else {
            reply(false, String(cString: strerror(errno)))
            return
        }

        reply(true, nil)
    }

    func setLaunchItemEnabled(_ enabled: Bool, target: String, reply: @escaping (Bool, String?) -> Void) {
        guard isAllowedLaunchTarget(target) else {
            reply(false, "The launchd target is outside the helper's allowed scope.")
            return
        }

        let result = Self.runProcess(
            executable: "/bin/launchctl",
            arguments: [enabled ? "enable" : "disable", target],
            timeout: 10
        )
        reply(result.status == 0, result.status == 0 ? nil : result.message)
    }

    func removeLegacyRootLaunchRule(reply: @escaping (Bool, String?) -> Void) {
        let path = PrivilegedHelperConstants.legacySudoersRulePath
        guard FileManager.default.fileExists(atPath: path) else {
            reply(true, nil)
            return
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func isAllowedLaunchTarget(_ target: String) -> Bool {
        let fields = target.split(separator: "/", omittingEmptySubsequences: false)
        let domain: String
        let label: String

        if fields.count == 2, fields[0] == "system" {
            domain = "system"
            label = String(fields[1])
        } else if fields.count == 3, fields[0] == "gui" {
            domain = "gui"
            label = String(fields[2])
        } else {
            return false
        }

        guard !label.isEmpty,
              label.unicodeScalars.allSatisfy(allowedLabelCharacters.contains) else {
            return false
        }

        if domain == "system" {
            return true
        }

        guard domain == "gui", let consoleUID = Self.consoleUserID() else {
            return false
        }

        return String(fields[1]) == String(consoleUID)
    }

    private static func consoleUserID() -> uid_t? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
              let ownerID = attributes[.ownerAccountID] as? NSNumber,
              ownerID.uint32Value != 0 else {
            return nil
        }
        return uid_t(ownerID.uint32Value)
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> (status: Int32, output: String, message: String) {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return (1, "", "The privileged operation timed out.")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output, message.isEmpty ? "The privileged operation failed." : message)
    }
}

private final class PrivilegedHelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service = PrivilegedHelperService()
    private let idleQueue = DispatchQueue(label: "com.xmodern.TaskMgmtMac.PrivilegedHelper.idle")
    private var idleExit: DispatchWorkItem?

    override init() {
        super.init()
        scheduleIdleExit()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        scheduleIdleExit()
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    private func scheduleIdleExit() {
        idleQueue.async { [weak self] in
            self?.idleExit?.cancel()
            let nextExit = DispatchWorkItem {
                exit(EXIT_SUCCESS)
            }
            self?.idleExit = nextExit
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: nextExit)
        }
    }
}

private func mainApplicationRequirement() -> String {
    let identifierClause = "identifier \"\(PrivilegedHelperConstants.mainApplicationIdentifier)\""
    guard let teamIdentifier = currentTeamIdentifier() else {
        // An ad-hoc helper has no stable team identity. Keep its XPC endpoint
        // closed instead of falling back to a spoofable identifier-only check.
        return "anchor apple and \(identifierClause)"
    }

    return "anchor apple generic and \(identifierClause) and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
}

private func currentTeamIdentifier() -> String? {
    var code: SecStaticCode?
    guard let executableURL = currentExecutableURL() else { return nil }
    guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess,
          let code else {
        return nil
    }

    var information: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let dictionary = information as? [String: Any] else {
        return nil
    }

    return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
}

private func currentExecutableURL() -> URL? {
    var bufferSize: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &bufferSize)
    guard bufferSize > 0 else { return nil }

    var buffer = [CChar](repeating: 0, count: Int(bufferSize))
    guard _NSGetExecutablePath(&buffer, &bufferSize) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).resolvingSymlinksInPath()
}

guard geteuid() == 0 else {
    fputs("TaskMgmtMacPrivilegedHelper must be launched by launchd as root.\n", stderr)
    exit(EXIT_FAILURE)
}

private let delegate = PrivilegedHelperListenerDelegate()
private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
listener.delegate = delegate
listener.setConnectionCodeSigningRequirement(mainApplicationRequirement())
listener.activate()
RunLoop.current.run()
