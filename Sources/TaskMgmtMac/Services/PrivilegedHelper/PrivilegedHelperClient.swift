import Foundation
import PrivilegedHelperIPC

enum PrivilegedHelperClientError: LocalizedError {
    case unavailable(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .operationFailed(let message):
            message
        }
    }
}

final class PrivilegedHelperClient: @unchecked Sendable {
    static let shared = PrivilegedHelperClient()

    private init() {}

    func helperVersion() async throws -> String {
        try await withProxy { proxy, reply in
            proxy.helperVersion { version in
                reply.resume(returning: version)
            }
        }
    }

    func collectPowerMetrics() async throws -> String {
        try await withProxy { proxy, reply in
            proxy.collectPowerMetrics { output, errorMessage in
                if let output {
                    reply.resume(returning: output)
                } else {
                    reply.resume(
                        throwing: PrivilegedHelperClientError.operationFailed(
                            errorMessage ?? "powermetrics failed in the privileged helper."
                        )
                    )
                }
            }
        }
    }

    func terminateProcess(_ pid: Int32) async throws {
        let _: Bool = try await withProxy { proxy, reply in
            proxy.terminateProcess(pid) { success, errorMessage in
                if success {
                    reply.resume(returning: true)
                } else {
                    reply.resume(
                        throwing: PrivilegedHelperClientError.operationFailed(
                            errorMessage ?? "The privileged helper could not end the process."
                        )
                    )
                }
            }
        }
    }

    func setLaunchItemEnabled(_ enabled: Bool, target: String) async throws {
        let _: Bool = try await withProxy { proxy, reply in
            proxy.setLaunchItemEnabled(enabled, target: target) { success, errorMessage in
                if success {
                    reply.resume(returning: true)
                } else {
                    reply.resume(
                        throwing: PrivilegedHelperClientError.operationFailed(
                            errorMessage ?? "The privileged helper could not update the launch item."
                        )
                    )
                }
            }
        }
    }

    func removeLegacyRootLaunchRule() async throws {
        let _: Bool = try await withProxy { proxy, reply in
            proxy.removeLegacyRootLaunchRule { success, errorMessage in
                if success {
                    reply.resume(returning: true)
                } else {
                    reply.resume(
                        throwing: PrivilegedHelperClientError.operationFailed(
                            errorMessage ?? "The legacy root launch rule could not be removed."
                        )
                    )
                }
            }
        }
    }

    private func withProxy<T: Sendable>(
        _ operation: @escaping @Sendable (PrivilegedHelperXPCProtocol, XPCReply<T>) -> Void
    ) async throws -> T {
        let connection = NSXPCConnection(
            machServiceName: PrivilegedHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)

        return try await withCheckedThrowingContinuation { continuation in
            let reply = XPCReply(continuation: continuation, connection: connection)
            connection.invalidationHandler = {
                reply.resume(
                    throwing: PrivilegedHelperClientError.unavailable(
                        "The privileged helper connection was invalidated."
                    )
                )
            }
            connection.interruptionHandler = {
                reply.resume(
                    throwing: PrivilegedHelperClientError.unavailable(
                        "The privileged helper connection was interrupted."
                    )
                )
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                reply.resume(
                    throwing: PrivilegedHelperClientError.unavailable(error.localizedDescription)
                )
            }

            guard let helper = proxy as? PrivilegedHelperXPCProtocol else {
                reply.resume(
                    throwing: PrivilegedHelperClientError.unavailable(
                        "The privileged helper XPC interface is unavailable."
                    )
                )
                return
            }

            operation(helper, reply)
        }
    }
}

private final class XPCReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var connection: NSXPCConnection?

    init(
        continuation: CheckedContinuation<Value, any Error>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func resume(returning value: Value) {
        finish(with: .success(value))
    }

    func resume(throwing error: any Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Value, any Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        continuation.resume(with: result)
    }
}
