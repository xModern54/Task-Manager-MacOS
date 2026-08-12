import AppKit
import SwiftUI

struct KernelPage: View {
    let snapshot: KernelSnapshot
    let cpuHistory: [Double]
    let wiredMemoryHistory: [Double]

    private let overviewColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            KernelCommandBar(snapshot: snapshot)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    KernelIdentityCard(snapshot: snapshot)

                    LazyVGrid(columns: overviewColumns, spacing: 10) {
                        KernelOverviewMetric(
                            label: "Kernel CPU",
                            value: formattedPercent(snapshot.kernelCPUPercent),
                            detail: "system mode",
                            icon: "waveform.path.ecg",
                            tint: KernelPalette.cyan
                        )
                        KernelOverviewMetric(
                            label: "Wired",
                            value: formattedBytes(snapshot.wiredMemoryBytes),
                            detail: "non-pageable",
                            icon: "memorychip",
                            tint: KernelPalette.violet
                        )
                        KernelOverviewMetric(
                            label: "Processes",
                            value: formattedInteger(snapshot.processCount),
                            detail: "\(formattedInteger(snapshot.threadCount)) threads",
                            icon: "square.stack.3d.up",
                            tint: KernelPalette.green
                        )
                        KernelOverviewMetric(
                            label: "Extensions",
                            value: formattedInteger(snapshot.loadedExtensionCount),
                            detail: "\(formattedInteger(snapshot.startedExtensionCount)) started",
                            icon: "puzzlepiece.extension",
                            tint: KernelPalette.orange
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        KernelCPUCard(snapshot: snapshot, history: cpuHistory)
                        KernelMemoryCard(snapshot: snapshot, history: wiredMemoryHistory)
                    }

                    KernelDriverCard(snapshot: snapshot)

                    HStack(alignment: .top, spacing: 12) {
                        KernelVMActivityCard(snapshot: snapshot)
                        KernelConfigurationCard(identity: snapshot.identity)
                    }
                }
                .padding(14)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KernelPalette.background)
    }
}

private struct KernelCommandBar: View {
    let snapshot: KernelSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Text("Kernel")
                .taskManagerFont(16, weight: .semibold)

            Text("XNU LIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(KernelPalette.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KernelPalette.green.opacity(0.10), in: Capsule())

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(snapshot.capturedAt == .distantPast ? KernelPalette.textMuted : KernelPalette.green)
                    .frame(width: 6, height: 6)

                if snapshot.capturedAt == .distantPast {
                    Text("Connecting")
                } else {
                    Text("Updated \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(KernelPalette.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct KernelIdentityCard: View {
    let snapshot: KernelSnapshot

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(KernelPalette.cyan.opacity(0.11))

                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(KernelPalette.cyan.opacity(0.28), lineWidth: 1)

                Image(systemName: "cpu")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(KernelPalette.cyan)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("DARWIN KERNEL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(KernelPalette.cyan)

                Text(snapshot.identity.release)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(KernelPalette.textPrimary)

                Text("\(snapshot.identity.xnuBuild)  •  build \(snapshot.identity.osBuild)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(KernelPalette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                PressureBadge(pressure: snapshot.memoryPressure)

                KernelIdentityValue(label: "ARCH", value: snapshot.identity.architecture.uppercased())
                KernelIdentityValue(label: "UPTIME", value: formattedUptime(snapshot.uptimeSeconds))
            }
        }
        .padding(16)
        .kernelCard()
    }
}

private struct PressureBadge: View {
    let pressure: KernelMemoryPressure

    private var color: Color {
        switch pressure {
        case .normal:
            KernelPalette.green
        case .warning:
            KernelPalette.orange
        case .critical:
            KernelPalette.red
        case .unknown:
            KernelPalette.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text("MEMORY \(pressure.rawValue.uppercased())")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.09), in: Capsule())
    }
}

private struct KernelIdentityValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .foregroundStyle(KernelPalette.textMuted)
            Text(value)
                .foregroundStyle(KernelPalette.textPrimary)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .lineLimit(1)
    }
}

private struct KernelOverviewMetric: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(KernelPalette.textMuted)

                Spacer(minLength: 2)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(KernelPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(detail)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(KernelPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 79, alignment: .leading)
        .kernelCard(tint: tint)
    }
}

private struct KernelCPUCard: View {
    let snapshot: KernelSnapshot
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KernelSectionHeader(
                eyebrow: "SCHEDULER",
                title: "CPU modes",
                value: formattedPercent(snapshot.totalCPUPercent),
                tint: KernelPalette.cyan
            )

            KernelHistoryGraph(samples: history, tint: KernelPalette.cyan, fixedMaximum: 100)
                .frame(height: 62)

            KernelModeBar(label: "KERNEL", value: snapshot.kernelCPUPercent, tint: KernelPalette.cyan)
            KernelModeBar(label: "USER", value: snapshot.userCPUPercent, tint: KernelPalette.violet)
            KernelModeBar(label: "IDLE", value: snapshot.idleCPUPercent, tint: KernelPalette.textMuted)

            HStack(spacing: 0) {
                ForEach(Array(snapshot.loadAverages.prefix(3).enumerated()), id: \.offset) { index, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(["1M", "5M", "15M"][index])
                            .foregroundStyle(KernelPalette.textMuted)
                        Text(value.formatted(.number.precision(.fractionLength(2))))
                            .foregroundStyle(KernelPalette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .kernelCard()
    }
}

private struct KernelMemoryCard: View {
    let snapshot: KernelSnapshot
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KernelSectionHeader(
                eyebrow: "VM SUBSYSTEM",
                title: "Kernel memory",
                value: formattedBytes(snapshot.wiredMemoryBytes),
                tint: KernelPalette.violet
            )

            KernelHistoryGraph(samples: history, tint: KernelPalette.violet)
                .frame(height: 62)

            KernelStatLine(label: "Wired / non-pageable", value: formattedBytes(snapshot.wiredMemoryBytes))
            KernelStatLine(label: "Anonymous resident", value: formattedBytes(snapshot.anonymousMemoryBytes))
            KernelStatLine(label: "Compressed", value: formattedBytes(snapshot.compressedMemoryBytes))
            KernelStatLine(label: "Extension images", value: formattedBytes(snapshot.driverImageMemoryBytes))

            HStack(spacing: 6) {
                Circle()
                    .fill(pressureColor(snapshot.memoryPressure))
                    .frame(width: 6, height: 6)
                Text("Pressure \(snapshot.memoryPressure.rawValue.lowercased())")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(KernelPalette.textSecondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .kernelCard()
    }
}

private struct KernelSectionHeader: View {
    let eyebrow: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Text(title)
                    .taskManagerFont(14, weight: .semibold)
            }

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(KernelPalette.textPrimary)
        }
    }
}

private struct KernelModeBar: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 44, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(KernelPalette.track)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(max(value / 100, 0), 1))
                }
            }
            .frame(height: 3)

            Text(formattedPercent(value))
                .frame(width: 42, alignment: .trailing)
                .foregroundStyle(KernelPalette.textPrimary)
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(KernelPalette.textMuted)
    }
}

private struct KernelStatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(KernelPalette.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .foregroundStyle(KernelPalette.textPrimary)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .lineLimit(1)
    }
}

private struct KernelDriverCard: View {
    let snapshot: KernelSnapshot

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(KernelPalette.orange)
                    .frame(width: 32, height: 32)
                    .background(KernelPalette.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver stack")
                        .taskManagerFont(14, weight: .semibold)
                    Text("Loaded kernel extensions and active I/O registry services")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(KernelPalette.textSecondary)
                }

                Spacer()

                Text("IOKIT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(KernelPalette.orange)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                DriverStat(label: "LOADED", value: formattedInteger(snapshot.loadedExtensionCount))
                DriverStat(label: "STARTED", value: formattedInteger(snapshot.startedExtensionCount))
                DriverStat(label: "THIRD PARTY", value: formattedInteger(snapshot.thirdPartyExtensionCount))
                DriverStat(label: "I/O NODES", value: formattedInteger(snapshot.ioServiceCount))
                DriverStat(label: "WIRED IMAGE", value: formattedBytes(snapshot.driverWiredMemoryBytes))
            }

            VStack(spacing: 5) {
                HStack {
                    Text("Extension image allocation")
                    Spacer()
                    Text(formattedBytes(snapshot.driverImageMemoryBytes))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(KernelPalette.textSecondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KernelPalette.track)
                        Capsule()
                            .fill(KernelPalette.orange)
                            .frame(
                                width: geometry.size.width * driverMemoryRatio(snapshot),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            Text("Footprint covers loaded extension images. macOS does not expose complete per-driver heap allocation through a public API.")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(KernelPalette.textMuted)
                .lineLimit(2)
        }
        .padding(13)
        .kernelCard(tint: KernelPalette.orange)
    }
}

private struct DriverStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(KernelPalette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(KernelPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KernelPalette.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct KernelVMActivityCard: View {
    let snapshot: KernelSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            KernelSectionHeader(
                eyebrow: "LIVE EVENTS",
                title: "VM activity",
                value: "/ SEC",
                tint: KernelPalette.green
            )

            KernelStatLine(label: "Page faults", value: formattedRate(snapshot.pageFaultsPerSecond))
            KernelStatLine(label: "Page-ins", value: formattedRate(snapshot.pageInsPerSecond))
            KernelStatLine(label: "Compressions", value: formattedRate(snapshot.compressionsPerSecond))
            KernelStatLine(label: "Decompressions", value: formattedRate(snapshot.decompressionsPerSecond))
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .kernelCard()
    }
}

private struct KernelConfigurationCard: View {
    let identity: KernelIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            KernelSectionHeader(
                eyebrow: "HOST LIMITS",
                title: "Kernel config",
                value: "STATIC",
                tint: KernelPalette.cyan
            )

            KernelStatLine(
                label: "CPU topology",
                value: "\(identity.physicalCoreCount)P / \(identity.logicalCoreCount)L"
            )
            KernelStatLine(label: "Page size", value: formattedBytes(identity.pageSizeBytes))
            KernelStatLine(label: "Max processes", value: formattedInteger(identity.maximumProcesses))
            KernelStatLine(label: "Max open files", value: formattedInteger(identity.maximumOpenFiles))
            KernelStatLine(label: "Host", value: identity.hostname)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .kernelCard()
    }
}

private struct KernelHistoryGraph: View {
    let samples: [Double]
    let tint: Color
    var fixedMaximum: Double?

    init(samples: [Double], tint: Color, fixedMaximum: Double? = nil) {
        self.samples = samples
        self.tint = tint
        self.fixedMaximum = fixedMaximum
    }

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for index in 1..<4 {
                let y = size.height * CGFloat(index) / 4
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(KernelPalette.grid), lineWidth: 0.5)

            guard samples.count > 1 else { return }
            let maximum = fixedMaximum ?? dynamicMaximum(samples)
            let minimum = fixedMaximum == nil ? dynamicMinimum(samples, maximum: maximum) : 0
            let span = max(maximum - minimum, 1)
            let step = size.width / CGFloat(samples.count - 1)

            var line = Path()
            for (index, sample) in samples.enumerated() {
                let normalized = min(max((sample - minimum) / span, 0), 1)
                let point = CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - CGFloat(normalized) * size.height
                )
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(0.09)))
            context.stroke(line, with: .color(tint), lineWidth: 1.4)
        }
        .background(KernelPalette.graphBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func dynamicMaximum(_ values: [Double]) -> Double {
        let maximum = values.max() ?? 1
        return maximum > 0 ? maximum * 1.02 : 1
    }

    private func dynamicMinimum(_ values: [Double], maximum: Double) -> Double {
        let positiveValues = values.filter { $0 > 0 }
        guard let minimum = positiveValues.min(), positiveValues.count > 1 else { return 0 }
        let padding = max((maximum - minimum) * 0.15, maximum * 0.005)
        return max(minimum - padding, 0)
    }
}

private struct KernelCardModifier: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(KernelPalette.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        tint?.opacity(0.17) ?? KernelPalette.cardBorder,
                        lineWidth: 1
                    )
            }
    }
}

private extension View {
    func kernelCard(tint: Color? = nil) -> some View {
        modifier(KernelCardModifier(tint: tint))
    }
}

private enum KernelPalette {
    static let background = adaptive(light: NSColor(calibratedWhite: 0.965, alpha: 1), dark: NSColor(calibratedWhite: 0.055, alpha: 1))
    static let card = adaptive(light: .white, dark: NSColor(calibratedWhite: 0.085, alpha: 1))
    static let inset = adaptive(light: NSColor(calibratedWhite: 0.965, alpha: 1), dark: NSColor.white.withAlphaComponent(0.045))
    static let graphBackground = adaptive(light: NSColor(calibratedWhite: 0.975, alpha: 1), dark: NSColor.black.withAlphaComponent(0.14))
    static let cardBorder = adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.07))
    static let grid = adaptive(light: NSColor.black.withAlphaComponent(0.065), dark: NSColor.white.withAlphaComponent(0.055))
    static let track = adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.08))
    static let textPrimary = WindowsTaskManagerTheme.textPrimary
    static let textSecondary = WindowsTaskManagerTheme.textSecondary
    static let textMuted = WindowsTaskManagerTheme.textMuted
    static let cyan = Color(red: 0.10, green: 0.67, blue: 0.72)
    static let violet = Color(red: 0.48, green: 0.45, blue: 0.88)
    static let green = Color(red: 0.17, green: 0.68, blue: 0.46)
    static let orange = Color(red: 0.91, green: 0.54, blue: 0.20)
    static let red = Color(red: 0.88, green: 0.30, blue: 0.31)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private func formattedPercent(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))))%"
}

private func formattedBytes(_ bytes: UInt64) -> String {
    guard bytes > 0 else { return "0 B" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(clamping: bytes))
}

private func formattedInteger<T: BinaryInteger>(_ value: T) -> String {
    Int64(clamping: value).formatted(.number.grouping(.automatic))
}

private func formattedRate(_ value: Double) -> String {
    switch value {
    case 1_000_000...:
        "\((value / 1_000_000).formatted(.number.precision(.fractionLength(1))))M/s"
    case 1_000...:
        "\((value / 1_000).formatted(.number.precision(.fractionLength(1))))K/s"
    default:
        "\(Int(value.rounded()).formatted())/s"
    }
}

private func formattedUptime(_ seconds: TimeInterval) -> String {
    let total = max(Int(seconds), 0)
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    let remainingSeconds = total % 60
    return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
}

private func pressureColor(_ pressure: KernelMemoryPressure) -> Color {
    switch pressure {
    case .normal:
        KernelPalette.green
    case .warning:
        KernelPalette.orange
    case .critical:
        KernelPalette.red
    case .unknown:
        KernelPalette.textMuted
    }
}

private func driverMemoryRatio(_ snapshot: KernelSnapshot) -> CGFloat {
    guard snapshot.wiredMemoryBytes > 0 else { return 0 }
    let ratio = Double(snapshot.driverImageMemoryBytes) / Double(snapshot.wiredMemoryBytes)
    return CGFloat(min(max(ratio, 0), 1))
}
