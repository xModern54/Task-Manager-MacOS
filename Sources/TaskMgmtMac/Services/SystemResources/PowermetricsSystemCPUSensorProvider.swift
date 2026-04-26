import Foundation

protocol SystemCPUSensorProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemCPUSensorSnapshot
}

struct SystemCPUSensorSnapshot: Sendable {
    var averageFrequencyMHz: Double?
    var performanceFrequencyMHz: Double?
    var efficiencyFrequencyMHz: Double?
    var temperatureCelsius: Double?
    var thermalPressure: String
    var lastError: String?

    var speedText: String? {
        averageFrequencyMHz.map(formatCPUFrequency)
    }

    static let unavailable = SystemCPUSensorSnapshot(
        averageFrequencyMHz: nil,
        performanceFrequencyMHz: nil,
        efficiencyFrequencyMHz: nil,
        temperatureCelsius: nil,
        thermalPressure: "--",
        lastError: nil
    )
}

func formatCPUFrequency(_ megahertz: Double) -> String {
    if megahertz >= 1000 {
        return String(format: "%.2f GHz", megahertz / 1000)
    }

    return "\(Int(megahertz.rounded())) MHz"
}

actor PowermetricsSystemCPUSensorProvider: SystemCPUSensorProviding {
    private var cachedSnapshot = SystemCPUSensorSnapshot.unavailable
    private var lastSampleDate: Date?

    private let minimumSampleInterval: TimeInterval = 5

    func snapshot(includeDetails: Bool) async -> SystemCPUSensorSnapshot {
        guard includeDetails else {
            return cachedSnapshot
        }

        if let lastSampleDate,
           Date().timeIntervalSince(lastSampleDate) < minimumSampleInterval {
            return cachedSnapshot
        }

        guard RootLaunchManager.isRunningAsRoot else {
            cachedSnapshot.lastError = "Root access required"
            return cachedSnapshot
        }

        do {
            let output = try await runPowermetrics()
            cachedSnapshot = PowermetricsCPUSensorParser.snapshot(from: output)
            lastSampleDate = Date()
        } catch {
            cachedSnapshot.lastError = error.localizedDescription
        }

        return cachedSnapshot
    }

    private func runPowermetrics() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
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

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let deadline = Date().addingTimeInterval(10)
                while process.isRunning {
                    if Date() > deadline {
                        process.terminate()
                        continuation.resume(throwing: PowermetricsCPUSensorError.timeout)
                        return
                    }

                    Thread.sleep(forTimeInterval: 0.05)
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: PowermetricsCPUSensorError.commandFailed(
                            errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }
}

private enum PowermetricsCPUSensorError: LocalizedError {
    case timeout
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            "powermetrics timed out"
        case .commandFailed(let message):
            message.isEmpty ? "powermetrics failed" : message
        }
    }
}

private enum PowermetricsCPUSensorParser {
    static func snapshot(from output: String) -> SystemCPUSensorSnapshot {
        let lines = output.components(separatedBy: .newlines)
        let frequencies = frequencyReadings(from: lines)

        return SystemCPUSensorSnapshot(
            averageFrequencyMHz: frequencies.average,
            performanceFrequencyMHz: frequencies.performance,
            efficiencyFrequencyMHz: frequencies.efficiency,
            temperatureCelsius: temperature(from: lines),
            thermalPressure: thermalPressure(from: lines) ?? "--",
            lastError: nil
        )
    }

    private static func frequencyReadings(from lines: [String]) -> (average: Double?, performance: Double?, efficiency: Double?) {
        var allValues: [Double] = []
        var performanceValues: [Double] = []
        var efficiencyValues: [Double] = []
        var currentCluster: CPUCluster?

        for line in lines {
            let lowercasedLine = line.lowercased()

            if lowercasedLine.hasPrefix("e-cluster") {
                currentCluster = .efficiency
            } else if lowercasedLine.hasPrefix("p-cluster") {
                currentCluster = .performance
            }

            guard lowercasedLine.contains("frequency:"),
                  let value = firstFrequencyMHz(in: line),
                  value > 0 else {
                continue
            }

            allValues.append(value)

            if lowercasedLine.hasPrefix("p-cluster") {
                performanceValues.append(value)
            } else if lowercasedLine.hasPrefix("e-cluster") {
                efficiencyValues.append(value)
            } else if lowercasedLine.hasPrefix("cpu ") {
                switch currentCluster {
                case .performance:
                    performanceValues.append(value)
                case .efficiency:
                    efficiencyValues.append(value)
                case nil:
                    break
                }
            }
        }

        return (
            average: average(allValues),
            performance: average(performanceValues),
            efficiency: average(efficiencyValues)
        )
    }

    private static func firstFrequencyMHz(in line: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(MHz|GHz)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line),
              let unitRange = Range(match.range(at: 2), in: line),
              let value = Double(line[valueRange]) else {
            return nil
        }

        return line[unitRange].lowercased() == "ghz" ? value * 1000 : value
    }

    private static func temperature(from lines: [String]) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(?:°\s*)?C\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        for line in lines where line.localizedCaseInsensitiveContains("temp") {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let value = Double(line[valueRange]) else {
                continue
            }

            return value
        }

        return nil
    }

    private static func thermalPressure(from lines: [String]) -> String? {
        for line in lines {
            let lowercasedLine = line.lowercased()
            guard (lowercasedLine.contains("thermal") && lowercasedLine.contains("pressure"))
                || lowercasedLine.contains("pressure level") else {
                continue
            }

            if let separatorIndex = line.firstIndex(where: { $0 == ":" || $0 == "=" }) {
                let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private enum CPUCluster {
    case performance
    case efficiency
}
