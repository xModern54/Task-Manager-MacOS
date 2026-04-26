import Foundation
@preconcurrency import XPC

private enum HelperCommand {
    static let ping = "ping"
    static let cpuPowerSnapshot = "cpu_power_snapshot"
}

private let listener = xpc_connection_create_mach_service(
    "com.xmodern.TaskMgmtMac.PrivilegedSensorHelper",
    nil,
    UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER)
)

xpc_connection_set_event_handler(listener) { peer in
    guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else {
        return
    }

    xpc_connection_set_event_handler(peer) { event in
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
            return
        }

        let command = xpc_dictionary_get_string(event, "command").map(String.init(cString:)) ?? ""
        let response: Result<String, Error>

        switch command {
        case HelperCommand.ping:
            response = .success("pong uid=\(getuid())")
        case HelperCommand.cpuPowerSnapshot:
            response = Result {
                try runPowermetrics()
            }
        default:
            response = .failure(HelperError.unsupportedCommand(command))
        }

        guard let reply = xpc_dictionary_create_reply(event) else {
            return
        }

        switch response {
        case .success(let payload):
            xpc_dictionary_set_bool(reply, "ok", true)
            xpc_dictionary_set_string(reply, "payload", payload)
        case .failure(let error):
            xpc_dictionary_set_bool(reply, "ok", false)
            xpc_dictionary_set_string(reply, "error", error.localizedDescription)
        }

        xpc_connection_send_message(peer, reply)
    }

    xpc_connection_resume(peer)
}

xpc_connection_resume(listener)
dispatchMain()

private func runPowermetrics() throws -> String {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
    process.arguments = [
        "-n", "1",
        "-i", "1000",
        "--samplers", "cpu_power,thermal",
        "--show-pstates",
        "--show-extra-power-info"
    ]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw HelperError.commandFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return output
}

private enum HelperError: LocalizedError {
    case unsupportedCommand(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let command):
            "Unsupported helper command: \(command)"
        case .commandFailed(let message):
            message.isEmpty ? "powermetrics failed" : message
        }
    }
}
