import Foundation

protocol SystemPrivilegedCPUSensorProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemPrivilegedCPUSensorSnapshot
}

struct SystemPrivilegedCPUSensorSnapshot: Sendable {
    var helperStatus: String
    let averageFrequencyMHz: Double?
    let performanceFrequencyMHz: Double?
    let efficiencyFrequencyMHz: Double?
    let temperatureCelsius: Double?
    let thermalPressure: String
    let lastError: String?

    var speedText: String? {
        averageFrequencyMHz.map(formatFrequency)
    }

    static let unavailable = SystemPrivilegedCPUSensorSnapshot(
        helperStatus: "Not requested",
        averageFrequencyMHz: nil,
        performanceFrequencyMHz: nil,
        efficiencyFrequencyMHz: nil,
        temperatureCelsius: nil,
        thermalPressure: "--",
        lastError: nil
    )
}

actor SMAppServicePrivilegedCPUSensorProvider: SystemPrivilegedCPUSensorProviding {
    private let client: PrivilegedSensorHelperClient
    private var cachedSnapshot = SystemPrivilegedCPUSensorSnapshot.unavailable
    private var didAttemptRegistration = false
    private var lastSampleDate: Date?

    private let minimumSampleInterval: TimeInterval = 5

    init(client: PrivilegedSensorHelperClient = .shared) {
        self.client = client
    }

    func snapshot(includeDetails: Bool) async -> SystemPrivilegedCPUSensorSnapshot {
        guard includeDetails else {
            return cachedSnapshot
        }

        if !didAttemptRegistration {
            didAttemptRegistration = true

            do {
                try client.register()
            } catch {
                let currentStatus = client.status
                if currentStatus != .enabled && currentStatus != .requiresApproval {
                    cachedSnapshot = SystemPrivilegedCPUSensorSnapshot(
                        helperStatus: statusDescription(currentStatus),
                        averageFrequencyMHz: cachedSnapshot.averageFrequencyMHz,
                        performanceFrequencyMHz: cachedSnapshot.performanceFrequencyMHz,
                        efficiencyFrequencyMHz: cachedSnapshot.efficiencyFrequencyMHz,
                        temperatureCelsius: cachedSnapshot.temperatureCelsius,
                        thermalPressure: cachedSnapshot.thermalPressure,
                        lastError: error.localizedDescription
                    )
                    return cachedSnapshot
                }
            }
        }

        let status = client.status
        if status != .enabled && status != .requiresApproval {
            cachedSnapshot = SystemPrivilegedCPUSensorSnapshot(
                helperStatus: statusDescription(status),
                averageFrequencyMHz: cachedSnapshot.averageFrequencyMHz,
                performanceFrequencyMHz: cachedSnapshot.performanceFrequencyMHz,
                efficiencyFrequencyMHz: cachedSnapshot.efficiencyFrequencyMHz,
                temperatureCelsius: cachedSnapshot.temperatureCelsius,
                thermalPressure: cachedSnapshot.thermalPressure,
                lastError: nil
            )
            return cachedSnapshot
        }

        if let lastSampleDate,
           Date().timeIntervalSince(lastSampleDate) < minimumSampleInterval {
            return cachedSnapshot
        }

        do {
            let output = try client.cpuPowerSnapshot()
            var parsedSnapshot = PowermetricsCPUSensorParser.snapshot(from: output)
            parsedSnapshot.helperStatus = statusDescription(client.status)
            cachedSnapshot = parsedSnapshot
            lastSampleDate = Date()
        } catch {
            let currentStatus = client.status
            cachedSnapshot = SystemPrivilegedCPUSensorSnapshot(
                helperStatus: statusDescription(currentStatus),
                averageFrequencyMHz: cachedSnapshot.averageFrequencyMHz,
                performanceFrequencyMHz: cachedSnapshot.performanceFrequencyMHz,
                efficiencyFrequencyMHz: cachedSnapshot.efficiencyFrequencyMHz,
                temperatureCelsius: cachedSnapshot.temperatureCelsius,
                thermalPressure: cachedSnapshot.thermalPressure,
                lastError: error.localizedDescription
            )
        }

        return cachedSnapshot
    }

    private func statusDescription(_ status: PrivilegedSensorHelperClient.Status) -> String {
        switch status {
        case .notRegistered:
            "Not registered"
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Requires approval"
        case .notFound:
            "Not found"
        @unknown default:
            "Unknown"
        }
    }
}

private enum PowermetricsCPUSensorParser {
    static func snapshot(from output: String) -> SystemPrivilegedCPUSensorSnapshot {
        let lines = output.components(separatedBy: .newlines)
        let frequencyReadings = frequencyReadings(from: lines)

        return SystemPrivilegedCPUSensorSnapshot(
            helperStatus: "Enabled",
            averageFrequencyMHz: frequencyReadings.average,
            performanceFrequencyMHz: frequencyReadings.performance,
            efficiencyFrequencyMHz: frequencyReadings.efficiency,
            temperatureCelsius: temperature(from: lines),
            thermalPressure: thermalPressure(from: lines) ?? "--",
            lastError: nil
        )
    }

    private static func frequencyReadings(from lines: [String]) -> (average: Double?, performance: Double?, efficiency: Double?) {
        var allValues: [Double] = []
        var performanceValues: [Double] = []
        var efficiencyValues: [Double] = []

        for line in lines {
            guard let value = firstFrequencyMHz(in: line) else {
                continue
            }

            let lowercasedLine = line.lowercased()
            allValues.append(value)

            if lowercasedLine.contains("p-cluster") || lowercasedLine.contains("performance") {
                performanceValues.append(value)
            } else if lowercasedLine.contains("e-cluster") || lowercasedLine.contains("efficiency") {
                efficiencyValues.append(value)
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
            guard lowercasedLine.contains("thermal") || lowercasedLine.contains("pressure") else {
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
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }
}

func formatFrequency(_ megahertz: Double) -> String {
    if megahertz >= 1000 {
        return String(format: "%.2f GHz", megahertz / 1000)
    }

    return String(format: "%.0f MHz", megahertz)
}
