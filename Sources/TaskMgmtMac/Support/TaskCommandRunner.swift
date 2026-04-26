import Foundation

struct TaskCommandResult: Sendable {
    let command: String
    let exitCode: Int32
    let output: String
    let errorOutput: String

    var combinedOutput: String {
        [output, errorOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum TaskCommandRunner {
    static func run(_ command: String) async throws -> TaskCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                let outputBuffer = CommandOutputBuffer()
                let errorBuffer = CommandOutputBuffer()

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    outputBuffer.append(handle.availableData)
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    errorBuffer.append(handle.availableData)
                }

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                process.terminationHandler = { process in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                    errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

                    continuation.resume(
                        returning: TaskCommandResult(
                            command: command,
                            exitCode: process.terminationStatus,
                            output: outputBuffer.string(),
                            errorOutput: errorBuffer.string()
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class CommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maximumBytes = 512_000

    func append(_ nextData: Data) {
        guard !nextData.isEmpty else { return }

        lock.lock()
        data.append(nextData)
        if data.count > maximumBytes {
            data = data.suffix(maximumBytes)
        }
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()

        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}
