@preconcurrency import AppKit
import Darwin
import Foundation
import Security

enum ProcessClipboardInfoBuilder {
    static func text(for row: ProcessTableRow) -> String {
        let metric = row.metric
        let diagnostics = ProcessDiagnostics(pid: metric.pid, executablePath: metric.executablePath)
        let copiedAt = ISO8601DateFormatter().string(from: Date())
        let appBundlePath = appBundlePath(from: metric.executablePath)
        let searchQuery = "\(metric.name) macOS"

        var lines: [String] = [
            "TaskMgmtMac process diagnostic context",
            "",
            "Suggested question:",
            "What is this macOS process, what software or service does it belong to, is it expected, and what are the risks of disabling, quitting, or removing it?",
            "",
            "Search query:",
            searchQuery,
            "",
            "Captured:",
            copiedAt,
            "",
            "Process identity:",
            "Name: \(metric.name)",
            "PID: \(metric.pid)",
            "Kind: \(rowKind(row))",
            "Parent PID: \(value(diagnostics.parentPID))",
            "Process group ID: \(value(diagnostics.processGroupID))",
            "User: \(diagnostics.userName ?? "Unavailable")",
            "UID: \(value(diagnostics.uid))",
            "GID: \(value(diagnostics.gid))",
            "Executable path: \(metric.executablePath ?? "Unavailable")",
            "App bundle path: \(appBundlePath ?? "Unavailable")",
            "Bundle identifier: \(diagnostics.bundleIdentifier ?? "Unavailable")",
            "Launch date: \(diagnostics.launchDate ?? "Unavailable")",
            "",
            "Resource snapshot:",
            "CPU: \(percent(metric.cpu))",
            "Memory: \(memory(metric.memoryMB))",
            "Disk: \(disk(metric.diskMBs))",
            "Network: \(network(metric.networkMbps))",
            "GPU: \(percent(metric.gpu))",
            "Power usage: \(metric.powerUsage.rawValue)",
            "Thread count: \(value(diagnostics.threadCount))",
            "Running threads: \(value(diagnostics.runningThreadCount))",
            "Open file count: \(value(diagnostics.openFileCount))",
            "",
            "Scheduling:",
            "Nice value: \(value(diagnostics.niceValue))",
            "Scheduler priority: \(value(diagnostics.schedulerPriority))",
            "Default scheduling policy: \(value(diagnostics.defaultSchedulingPolicy))",
            "",
            "Command line:",
            diagnostics.commandLine ?? "Unavailable",
            "",
            "Code signature:",
            "Signing identifier: \(diagnostics.signature?.identifier ?? "Unavailable")",
            "Team ID: \(diagnostics.signature?.teamIdentifier ?? "Unavailable")",
            "Signature format: \(diagnostics.signature?.format ?? "Unavailable")",
            "Signature source: \(diagnostics.signature?.source ?? "Unavailable")",
            "Signature valid: \(diagnostics.signature?.isValidText ?? "Unavailable")",
            "Apple signed: \(diagnostics.signature?.isAppleSignedText ?? "Unavailable")",
            "",
            "File:",
            "Owner: \(diagnostics.fileOwner ?? "Unavailable")",
            "POSIX permissions: \(diagnostics.filePermissions ?? "Unavailable")",
            "",
            "Privacy note:",
            "Environment variables are intentionally not included because they can contain tokens, secrets, and private paths."
        ]

        if row.isGroup {
            lines.append(contentsOf: [
                "",
                "Grouped child processes:"
            ])
            lines.append(contentsOf: row.children.map { "\($0.name) (PID \($0.pid))" })
        }

        return lines.joined(separator: "\n")
    }

    private static func rowKind(_ row: ProcessTableRow) -> String {
        switch row.kind {
        case .process:
            "Process"
        case .group:
            "Application group"
        case .child:
            "Grouped process"
        }
    }

    fileprivate static func appBundlePath(from executablePath: String?) -> String? {
        guard let executablePath else { return nil }

        let components = URL(fileURLWithPath: executablePath).pathComponents
        var pathComponents: [String] = []

        for component in components {
            pathComponents.append(component)

            guard component.hasSuffix(".app") else {
                continue
            }

            return NSString.path(withComponents: pathComponents)
        }

        return nil
    }

    private static func percent(_ value: Double) -> String {
        value == 0 ? "0%" : String(format: "%.1f%%", value)
    }

    private static func memory(_ value: Double) -> String {
        String(format: "%.1f MB", value)
    }

    private static func disk(_ value: Double) -> String {
        value == 0 ? "0 MB/s" : String(format: "%.1f MB/s", value)
    }

    private static func network(_ value: Double) -> String {
        value == 0 ? "0 Mbps" : String(format: "%.1f Mbps", value)
    }

    private static func value<T>(_ value: T?) -> String {
        guard let value else { return "Unavailable" }
        return "\(value)"
    }
}

private struct ProcessDiagnostics {
    let parentPID: Int?
    let processGroupID: Int?
    let uid: UInt32?
    let gid: UInt32?
    let userName: String?
    let niceValue: Int?
    let schedulerPriority: Int?
    let defaultSchedulingPolicy: Int?
    let threadCount: Int?
    let runningThreadCount: Int?
    let openFileCount: Int?
    let commandLine: String?
    let bundleIdentifier: String?
    let launchDate: String?
    let signature: CodeSignatureInfo?
    let fileOwner: String?
    let filePermissions: String?

    init(pid: Int, executablePath: String?) {
        let taskInfo = Self.taskAllInfo(for: pid)
        let runningApplication = NSRunningApplication(processIdentifier: pid_t(pid))

        parentPID = taskInfo.map { Int($0.pbsd.pbi_ppid) }
        processGroupID = taskInfo.map { Int($0.pbsd.pbi_pgid) }
        uid = taskInfo?.pbsd.pbi_uid
        gid = taskInfo?.pbsd.pbi_gid
        userName = taskInfo.flatMap { Self.userName(for: $0.pbsd.pbi_uid) }
        niceValue = taskInfo.map { Int($0.pbsd.pbi_nice) }
        schedulerPriority = taskInfo.map { Int($0.ptinfo.pti_priority) }
        defaultSchedulingPolicy = taskInfo.map { Int($0.ptinfo.pti_policy) }
        threadCount = taskInfo.map { Int($0.ptinfo.pti_threadnum) }
        runningThreadCount = taskInfo.map { Int($0.ptinfo.pti_numrunning) }
        openFileCount = taskInfo.map { Int($0.pbsd.pbi_nfiles) }
        commandLine = Self.commandLine(for: pid)
        bundleIdentifier = runningApplication?.bundleIdentifier ?? Self.bundleIdentifier(for: executablePath)
        launchDate = runningApplication?.launchDate.map { ISO8601DateFormatter().string(from: $0) }
        signature = Self.codeSignature(for: executablePath)
        fileOwner = Self.fileOwner(for: executablePath)
        filePermissions = Self.filePermissions(for: executablePath)
    }

    private static func taskAllInfo(for pid: Int) -> proc_taskallinfo? {
        guard pid > 0 else { return nil }

        var taskInfo = proc_taskallinfo()
        let taskInfoSize = MemoryLayout<proc_taskallinfo>.stride
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: taskInfoSize) { taskInfoPointer in
                proc_pidinfo(pid_t(pid), PROC_PIDTASKALLINFO, 0, taskInfoPointer, Int32(taskInfoSize))
            }
        }

        guard result == taskInfoSize else { return nil }
        return taskInfo
    }

    private static func userName(for uid: uid_t) -> String? {
        guard let password = getpwuid(uid),
              let name = password.pointee.pw_name else {
            return nil
        }

        return String(cString: name)
    }

    private static func commandLine(for pid: Int) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        let argc = buffer.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: Int32.self)
        }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 {
            index += 1
        }
        while index < size, buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        for _ in 0..<argc {
            let start = index
            while index < size, buffer[index] != 0 {
                index += 1
            }

            if start < index {
                let argument = buffer[start..<index].map { UInt8(bitPattern: $0) }
                arguments.append(String(decoding: argument, as: UTF8.self))
            }

            while index < size, buffer[index] == 0 {
                index += 1
            }
        }

        guard !arguments.isEmpty else { return nil }
        return arguments.joined(separator: " ")
    }

    private static func bundleIdentifier(for executablePath: String?) -> String? {
        guard let appBundlePath = ProcessClipboardInfoBuilder.appBundlePath(from: executablePath),
              let bundle = Bundle(path: appBundlePath) else {
            return nil
        }

        return bundle.bundleIdentifier
    }

    private static func codeSignature(for executablePath: String?) -> CodeSignatureInfo? {
        guard let executablePath else { return nil }

        let signingPath = ProcessClipboardInfoBuilder.appBundlePath(from: executablePath) ?? executablePath
        let signingURL = URL(fileURLWithPath: signingPath)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(signingURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        let dictionary = signingInformation as NSDictionary?

        let validStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        let appleStatus = Self.appleSignedStatus(for: staticCode)

        return CodeSignatureInfo(
            identifier: dictionary?[kSecCodeInfoIdentifier] as? String,
            teamIdentifier: dictionary?[kSecCodeInfoTeamIdentifier] as? String,
            format: dictionary?[kSecCodeInfoFormat] as? String,
            source: dictionary?[kSecCodeInfoSource] as? String,
            isValid: validStatus == errSecSuccess,
            validationStatus: validStatus,
            isAppleSigned: appleStatus == errSecSuccess,
            appleSigningStatus: appleStatus,
            signingInfoStatus: copyStatus
        )
    }

    private static func appleSignedStatus(for staticCode: SecStaticCode) -> OSStatus {
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString("anchor apple" as CFString, SecCSFlags(), &requirement)
        guard requirementStatus == errSecSuccess, let requirement else {
            return requirementStatus
        }

        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement)
    }

    private static func fileOwner(for executablePath: String?) -> String? {
        guard let executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath) else {
            return nil
        }

        return attributes[.ownerAccountName] as? String
    }

    private static func filePermissions(for executablePath: String?) -> String? {
        guard let executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return nil
        }

        return String(format: "%03o", permissions.intValue & 0o777)
    }
}

private struct CodeSignatureInfo {
    let identifier: String?
    let teamIdentifier: String?
    let format: String?
    let source: String?
    let isValid: Bool
    let validationStatus: OSStatus
    let isAppleSigned: Bool
    let appleSigningStatus: OSStatus
    let signingInfoStatus: OSStatus

    var isValidText: String {
        statusText(isValid, status: validationStatus)
    }

    var isAppleSignedText: String {
        statusText(isAppleSigned, status: appleSigningStatus)
    }

    private func statusText(_ value: Bool, status: OSStatus) -> String {
        if value {
            return "Yes"
        }

        return "No (OSStatus \(status))"
    }
}
