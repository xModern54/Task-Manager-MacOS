import Foundation
import ServiceManagement
@preconcurrency import XPC

struct PrivilegedSensorHelperClient: Sendable {
    static let shared = PrivilegedSensorHelperClient()

    static let label = "com.xmodern.TaskMgmtMac.PrivilegedSensorHelper"
    static let plistName = "\(label).plist"
    static let machServiceName = label

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            service.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func ping() throws -> String {
        try request(command: "ping")
    }

    func cpuPowerSnapshot() throws -> String {
        try request(command: "cpu_power_snapshot")
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    private func request(command: String) throws -> String {
        let connection = xpc_connection_create_mach_service(
            Self.machServiceName,
            nil,
            UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED)
        )

        xpc_connection_set_event_handler(connection) { _ in }
        xpc_connection_resume(connection)
        defer {
            xpc_connection_cancel(connection)
        }

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "command", command)

        let reply = xpc_connection_send_message_with_reply_sync(connection, message)

        if xpc_get_type(reply) == XPC_TYPE_ERROR {
            let description = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION)
                .map(String.init(cString:)) ?? "Unknown XPC error"
            throw PrivilegedSensorHelperError.xpc(description)
        }

        let ok = xpc_dictionary_get_bool(reply, "ok")
        let payload = xpc_dictionary_get_string(reply, "payload").map(String.init(cString:)) ?? ""

        guard ok else {
            let error = xpc_dictionary_get_string(reply, "error").map(String.init(cString:)) ?? "Unknown helper error"
            throw PrivilegedSensorHelperError.helper(error)
        }

        return payload
    }
}

enum PrivilegedSensorHelperError: LocalizedError {
    case xpc(String)
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .xpc(let message):
            "XPC error: \(message)"
        case .helper(let message):
            message
        }
    }
}
