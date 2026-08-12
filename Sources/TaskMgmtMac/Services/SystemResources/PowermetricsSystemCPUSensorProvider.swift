import Foundation

protocol SystemCPUSensorProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemCPUSensorSnapshot
}

struct SystemCPUSensorSnapshot: Sendable {
    var averageFrequencyMHz: Double?
    var performanceFrequencyMHz: Double?
    var efficiencyFrequencyMHz: Double?
    var temperatureCelsius: Double?
    var cpuPowerWatts: Double?
    var gpuPowerWatts: Double?
    var anePowerWatts: Double?
    var combinedPowerWatts: Double?
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
        cpuPowerWatts: nil,
        gpuPowerWatts: nil,
        anePowerWatts: nil,
        combinedPowerWatts: nil,
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

        let hidTemperature = IOHIDSystemCPUTemperatureReader.temperatureCelsius()

        do {
            let output = try await PrivilegedHelperClient.shared.collectPowerMetrics()
            var nextSnapshot = PowermetricsCPUSensorParser.snapshot(from: output)
            nextSnapshot.temperatureCelsius = nextSnapshot.temperatureCelsius ?? hidTemperature
            cachedSnapshot = nextSnapshot
            lastSampleDate = Date()
        } catch {
            cachedSnapshot.temperatureCelsius = hidTemperature ?? cachedSnapshot.temperatureCelsius
            cachedSnapshot.lastError = error.localizedDescription
            lastSampleDate = Date()
        }

        return cachedSnapshot
    }

}

enum PowermetricsCPUSensorParser {
    static func snapshot(from output: String) -> SystemCPUSensorSnapshot {
        let lines = output.components(separatedBy: .newlines)
        let frequencies = frequencyReadings(from: lines)

        return SystemCPUSensorSnapshot(
            averageFrequencyMHz: frequencies.average,
            performanceFrequencyMHz: frequencies.performance,
            efficiencyFrequencyMHz: frequencies.efficiency,
            temperatureCelsius: temperature(from: lines),
            cpuPowerWatts: powerWatts(from: lines, labelPrefix: "CPU Power"),
            gpuPowerWatts: powerWatts(from: lines, labelPrefix: "GPU Power"),
            anePowerWatts: powerWatts(from: lines, labelPrefix: "ANE Power"),
            combinedPowerWatts: powerWatts(from: lines, labelPrefix: "Combined Power"),
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
            let lineCluster = clusterKind(from: lowercasedLine)

            if let lineCluster {
                currentCluster = lineCluster
            }

            guard lowercasedLine.contains("frequency"),
                  let value = firstFrequencyMHz(in: line),
                  value >= 0 else {
                continue
            }

            allValues.append(value)

            if let lineCluster {
                append(value, to: lineCluster, performanceValues: &performanceValues, efficiencyValues: &efficiencyValues)
            } else if lowercasedLine.hasPrefix("cpu ") {
                if let currentCluster {
                    append(value, to: currentCluster, performanceValues: &performanceValues, efficiencyValues: &efficiencyValues)
                }
            }
        }

        return (
            average: average(allValues),
            performance: average(performanceValues),
            efficiency: average(efficiencyValues)
        )
    }

    private static func clusterKind(from lowercasedLine: String) -> CPUCluster? {
        let line = lowercasedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let clusterName = line.prefix { character in
            character != ":" && character != "(" && !character.isWhitespace
        }

        // Apple Silicon generations have used E/P-Cluster, numbered variants
        // such as P0-Cluster, and the newer S/Super naming for fast cores.
        let efficiencyPattern = #"^(?:e[0-9]*-?cluster|efficiency(?:-?cluster)?)$"#
        let performancePattern = #"^(?:p[0-9]*-?cluster|s[0-9]*-?cluster|performance(?:-?cluster)?|super(?:-?cluster)?)$"#

        if clusterName.range(of: efficiencyPattern, options: .regularExpression) != nil {
            return .efficiency
        }

        if clusterName.range(of: performancePattern, options: .regularExpression) != nil {
            return .performance
        }

        return nil
    }

    private static func append(
        _ value: Double,
        to cluster: CPUCluster,
        performanceValues: inout [Double],
        efficiencyValues: inout [Double]
    ) {
        switch cluster {
        case .performance:
            performanceValues.append(value)
        case .efficiency:
            efficiencyValues.append(value)
        }
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

    private static func powerWatts(from lines: [String], labelPrefix: String) -> Double? {
        let lowercasedPrefix = labelPrefix.lowercased()
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(mW|W)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        for line in lines where line.lowercased().hasPrefix(lowercasedPrefix) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line),
                  let unitRange = Range(match.range(at: 2), in: line),
                  let value = Double(line[valueRange]) else {
                continue
            }

            return line[unitRange].lowercased() == "mw" ? value / 1000 : value
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
