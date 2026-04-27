import Foundation
import SwiftUI

struct PerformancePage: View {
    let summary: ProcessSummary
    let cpuHistory: [Double]
    let memoryHistory: [Double]
    let gpuSnapshot: SystemGPUSnapshot
    let gpuHistory: [Double]
    let diskSnapshot: SystemDiskSnapshot
    let diskHistory: [Double]
    let networkSnapshot: SystemNetworkSnapshot
    let networkHistory: [Double]
    let npuSnapshot: SystemNPUSnapshot
    let npuHistory: [Double]
    let batterySnapshot: SystemBatterySnapshot
    let batteryHistory: [Double]
    let cpuSensorSnapshot: SystemCPUSensorSnapshot
    @Binding var selectedDeviceID: PerformanceDevice.ID

    @State private var processorName: String?
    @State private var processorSpeedText: String?
    @State private var systemBootDate: Date?
    @State private var didLoadProcessorName = false

    private let cpuInfoProvider: any SystemCPUInfoProviding = SysctlCPUInfoProvider()

    private var devices: [PerformanceDevice] {
        PerformanceDevice.mockDevices.compactMap { device in
            if device.kind == .cpu {
                return device.updatingCPUStats(
                    from: summary,
                    samples: cpuHistory,
                    sensorSnapshot: cpuSensorSnapshot,
                    fallbackSpeedText: processorSpeedText ?? "--",
                    uptimeText: uptimeText
                )
            } else if device.kind == .memory {
                return device.updatingMemoryStats(
                    from: summary,
                    samples: memoryHistory,
                    usedBytes: resolvedMemoryUsedBytes(summary),
                    totalBytes: resolvedMemoryTotalBytes(summary),
                    compressedBytes: summary.memoryCompressedBytes,
                    cachedBytes: summary.memoryCachedBytes,
                    wiredBytes: summary.memoryWiredBytes,
                    swapUsedBytes: summary.memorySwapUsedBytes,
                    swapTotalBytes: summary.memorySwapTotalBytes
                )
            } else if device.kind == .gpu {
                return device.updatingGPUStats(
                    from: gpuSnapshot,
                    samples: gpuHistory,
                    sensorSnapshot: cpuSensorSnapshot
                )
            } else if device.kind == .disk {
                return device.updatingDiskStats(
                    from: diskSnapshot,
                    samples: diskHistory
                )
            } else if device.kind == .ethernet {
                return device.updatingNetworkStats(
                    from: networkSnapshot,
                    samples: networkHistory
                )
            } else if device.kind == .npu {
                return device.updatingNPUStats(
                    from: npuSnapshot,
                    samples: npuHistory
                )
            } else if device.kind == .battery {
                guard batterySnapshot.isPresent else { return nil }
                return device.updatingBatteryStats(
                    from: batterySnapshot,
                    samples: batteryHistory,
                    sensorSnapshot: cpuSensorSnapshot
                )
            }

            return device
        }
    }

    private func resolvedMemoryTotalBytes(_ summary: ProcessSummary) -> UInt64 {
        if summary.memoryTotalBytes > 0 {
            return summary.memoryTotalBytes
        }

        return ProcessInfo.processInfo.physicalMemory
    }

    private func resolvedMemoryUsedBytes(_ summary: ProcessSummary) -> UInt64 {
        if summary.memoryUsedBytes > 0 {
            return min(summary.memoryUsedBytes, resolvedMemoryTotalBytes(summary))
        }

        guard resolvedMemoryTotalBytes(summary) > 0, summary.memory > 0 else { return 0 }
        let calculated = Double(resolvedMemoryTotalBytes(summary)) * Double(summary.memory) / 100
        return min(UInt64(calculated.rounded()), resolvedMemoryTotalBytes(summary))
    }

    private var uptimeText: String {
        guard let systemBootDate else { return "--" }

        let uptimeSeconds = max(Int(Date().timeIntervalSince(systemBootDate)), 0)
        let days = uptimeSeconds / 86_400
        let hours = (uptimeSeconds % 86_400) / 3_600
        let minutes = (uptimeSeconds % 3_600) / 60
        let seconds = uptimeSeconds % 60

        return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }

    private var selectedDevice: PerformanceDevice {
        devices.first { $0.id == selectedDeviceID } ?? devices[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            PerformanceCommandBar()

            HStack(spacing: 0) {
                PerformanceDeviceList(
                    devices: devices,
                    selectedDeviceID: $selectedDeviceID
                )

                PerformanceDetail(
                    device: selectedDevice,
                    processorName: processorName
                )
            }
        }
        .background(WindowsTaskManagerTheme.content)
        .task {
            guard !didLoadProcessorName else { return }
            didLoadProcessorName = true
            processorName = cpuInfoProvider.processorName()
            processorSpeedText = cpuInfoProvider.processorSpeedText()
            systemBootDate = cpuInfoProvider.systemBootDate()
        }
    }
}

private struct PerformanceCommandBar: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Performance")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 16)

            Spacer()

            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.square.on.square")
                        .taskManagerFont(15)

                    Text("Run new task")
                        .taskManagerFont(13)
                }
                .frame(height: 50)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(width: 1, height: 30)
                .padding(.horizontal, 4)

            Image(systemName: "ellipsis")
                .taskManagerFont(18, weight: .bold)
                .frame(width: 46, height: 50)
        }
        .frame(height: 61)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct PerformanceDeviceList: View {
    let devices: [PerformanceDevice]
    @Binding var selectedDeviceID: PerformanceDevice.ID

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                ForEach(devices) { device in
                    PerformanceDeviceRow(
                        device: device,
                        isSelected: selectedDeviceID == device.id
                    )
                    .onTapGesture {
                        selectedDeviceID = device.id
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
        }
        .frame(width: 220)
        .background(WindowsTaskManagerTheme.content)
    }
}

private struct PerformanceDeviceRow: View {
    let device: PerformanceDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            PerformanceGraphView(samples: device.samples, color: device.color, fill: false)
                .frame(width: 60, height: 45)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                    .taskManagerFont(15)
                    .lineLimit(1)

                if !device.subtitle.isEmpty {
                    Text(device.subtitle)
                        .taskManagerFont(11)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                        .lineLimit(1)
                }

                Text(device.valueText)
                    .taskManagerFont(11)
                    .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? device.color.opacity(0.08) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    device.outlineColor.opacity(isSelected ? 1 : 0.42),
                    lineWidth: isSelected ? 2.4 : 1.2
                )
        }
        .shadow(color: isSelected ? device.outlineColor.opacity(0.16) : .clear, radius: 4, x: 0, y: 0)
        .contentShape(Rectangle())
    }
}

private struct PerformanceDetail: View {
    let device: PerformanceDevice
    let processorName: String?

    private var detailSubtitle: String {
        if device.kind == .cpu, let processorName {
            return processorName
        }

        return device.detailSubtitle
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(device.detailTitle)
                        .taskManagerFont(28)
                        .lineLimit(1)

                    Spacer()

                    Text(detailSubtitle)
                        .taskManagerFont(13)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }

                switch device.kind {
                case .cpu:
                    CPUPerformanceDetail(device: device)
                case .memory:
                    MemoryPerformanceDetail(device: device)
                case .disk:
                    DiskPerformanceDetail(device: device)
                case .ethernet:
                    EthernetPerformanceDetail(device: device)
                case .gpu:
                    GPUPerformanceDetail(device: device)
                case .npu:
                    NPUPerformanceDetail(device: device)
                case .battery:
                    BatteryPerformanceDetail(device: device)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WindowsTaskManagerTheme.table)
    }
}

private struct CPUPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("% Utilization over 60 seconds")
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                ForEach(0..<12, id: \.self) { index in
                    PerformanceGraphView(samples: rotated(device.samples, by: index), color: device.color)
                        .frame(height: 58)
                }
            }

            StatGrid(stats: device.stats, columns: 3)
        }
    }
}

private struct MemoryPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "Memory usage", trailing: device.valueText, device: device, height: 205, fill: true)

            Text("Memory composition")
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            HStack(spacing: 0) {
                Rectangle().fill(device.color.opacity(0.65)).frame(width: 78)
                Rectangle().fill(device.color.opacity(0.18)).frame(width: 34)
                Color.clear
            }
            .frame(height: 52)
            .overlay {
                Rectangle().stroke(device.color, lineWidth: 1)
            }

            StatGrid(stats: device.stats, columns: 3)
        }
    }
}

private struct DiskPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "Active time", trailing: "100%", device: device, height: 255)
            LabeledGraph(title: "Disk transfer rate", trailing: "100 KB/s", device: device, height: 65)
            StatGrid(stats: device.stats, columns: 3)
        }
    }
}

private struct EthernetPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "Throughput", trailing: device.valueText, device: device, height: 340, fill: true)
            StatGrid(stats: device.stats, columns: 2)
        }
    }
}

private struct GPUPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "% Utilization", trailing: "100%", device: device, height: 340, fill: true)
            StatGrid(stats: device.stats, columns: 3)
        }
    }
}

private struct NPUPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "% Utilization", trailing: device.valueText, device: device, height: 340, fill: true)
            StatGrid(stats: device.stats, columns: 3)
        }
    }
}

private struct BatteryPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledGraph(title: "Battery level", trailing: "100%", device: device, height: 340, fill: true)
            StatGrid(stats: device.stats, columns: 2)
        }
    }
}

private struct LabeledGraph: View {
    let title: String
    let trailing: String
    let device: PerformanceDevice
    let height: CGFloat
    var fill = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(trailing)
            }
            .taskManagerFont(12)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

            PerformanceGraphView(samples: device.samples, color: device.color, fill: fill)
                .frame(height: height)

            HStack {
                Text("60 seconds")
                Spacer()
                Text("0")
            }
            .taskManagerFont(10)
            .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
        }
    }
}

private struct StatGrid: View {
    let stats: [PerformanceStat]
    let columns: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 8) {
            ForEach(stats, id: \.self) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .taskManagerFont(11)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                        .lineLimit(1)

                    Text(stat.value)
                        .taskManagerFont(18)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(.top, 4)
    }
}

private func rotated(_ values: [Double], by offset: Int) -> [Double] {
    guard !values.isEmpty else { return values }
    let split = offset % values.count
    return Array(values[split...] + values[..<split])
}

private extension PerformanceDevice {
    func updatingCPUStats(
        from summary: ProcessSummary,
        samples: [Double],
        sensorSnapshot: SystemCPUSensorSnapshot,
        fallbackSpeedText: String,
        uptimeText: String
    ) -> PerformanceDevice {
        guard kind == .cpu else { return self }

        let speedText = sensorSnapshot.speedText ?? fallbackSpeedText
        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Utilization":
                PerformanceStat(label: stat.label, value: "\(summary.cpu)%")
            case "Processes":
                PerformanceStat(label: stat.label, value: "\(summary.processCount)")
            case "Threads":
                PerformanceStat(label: stat.label, value: "\(summary.threadCount)")
            case "Speed":
                PerformanceStat(label: stat.label, value: speedText)
            case "Up time":
                PerformanceStat(label: stat.label, value: uptimeText)
            default:
                stat
            }
        }

        let sensorStats = [
            PerformanceStat(label: "P-core speed", value: sensorSnapshot.performanceFrequencyMHz.map { formatCPUFrequency($0) } ?? "--"),
            PerformanceStat(label: "E-core speed", value: sensorSnapshot.efficiencyFrequencyMHz.map { formatCPUFrequency($0) } ?? "--"),
            PerformanceStat(label: "Temperature", value: formattedTemperature(sensorSnapshot.temperatureCelsius)),
            PerformanceStat(label: "Package power", value: formattedWatts(sensorSnapshot.combinedPowerWatts)),
            PerformanceStat(label: "CPU power", value: formattedWatts(sensorSnapshot.cpuPowerWatts)),
            PerformanceStat(label: "Thermal pressure", value: sensorSnapshot.thermalPressure),
            PerformanceStat(label: "Sensor error", value: sensorSnapshot.lastError ?? "--")
        ]

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            valueText: "\(summary.cpu)% \(speedText)",
            detailTitle: detailTitle,
            detailSubtitle: detailSubtitle,
            color: color,
            samples: samples.isEmpty ? [0] : samples,
            stats: updatedStats + sensorStats
        )
    }

    func updatingMemoryStats(
        from summary: ProcessSummary,
        samples: [Double],
        usedBytes: UInt64,
        totalBytes: UInt64,
        compressedBytes: UInt64,
        cachedBytes: UInt64,
        wiredBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64
    ) -> PerformanceDevice {
        guard kind == .memory else { return self }

        let clampedTotalBytes = max(totalBytes, 1)
        let clampedUsedBytes = min(usedBytes, clampedTotalBytes)
        let availableBytes = clampedTotalBytes - clampedUsedBytes
        let compressedText = "\(formattedMegabytes(compressedBytes))"

        let updatedStats = stats.map { stat in
            switch stat.label {
            case "In use (Compressed)":
                PerformanceStat(
                    label: stat.label,
                    value: "\(formattedGigabytes(clampedUsedBytes)) (\(compressedText))"
                )
            case "Available":
                PerformanceStat(label: stat.label, value: formattedGigabytes(availableBytes))
            case "Committed":
                PerformanceStat(
                    label: stat.label,
                    value: "\(formattedGigabytes(clampedUsedBytes))/\(formattedGigabytes(clampedTotalBytes))"
                )
            case "Cached":
                PerformanceStat(label: stat.label, value: formattedGigabytes(cachedBytes))
            case "Wired":
                PerformanceStat(label: stat.label, value: formattedGigabytes(wiredBytes))
            case "Swap used":
                PerformanceStat(label: stat.label, value: formattedSwapUsage(usedBytes: swapUsedBytes, totalBytes: swapTotalBytes))
            default:
                stat
            }
        }

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            valueText: "\(formattedGigabytes(clampedUsedBytes))/\(formattedGigabytes(clampedTotalBytes)) (\(summary.memory)%)",
            detailTitle: detailTitle,
            detailSubtitle: formattedGigabytes(clampedTotalBytes),
            color: color,
            samples: samples.isEmpty ? [0] : samples,
            stats: updatedStats
        )
    }

    func updatingGPUStats(
        from snapshot: SystemGPUSnapshot,
        samples: [Double],
        sensorSnapshot: SystemCPUSensorSnapshot
    ) -> PerformanceDevice {
        guard kind == .gpu else { return self }

        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Utilization":
                PerformanceStat(label: stat.label, value: "\(snapshot.usagePercent)%")
            case "GPU memory":
                PerformanceStat(label: stat.label, value: formattedMegabytes(snapshot.inUseMemoryBytes))
            case "Allocated memory":
                PerformanceStat(label: stat.label, value: formattedGigabytes(snapshot.allocatedMemoryBytes))
            case "Memory type":
                PerformanceStat(label: stat.label, value: snapshot.hasUnifiedMemory ? "Unified" : "Dedicated")
            case "GPU cores":
                PerformanceStat(label: stat.label, value: snapshot.coreCount.map(String.init) ?? "--")
            case "GPU power":
                PerformanceStat(label: stat.label, value: formattedWatts(sensorSnapshot.gpuPowerWatts))
            default:
                stat
            }
        }

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: snapshot.name,
            valueText: "\(snapshot.usagePercent)%",
            detailTitle: detailTitle,
            detailSubtitle: snapshot.name,
            color: color,
            samples: samples.isEmpty ? [0] : samples,
            stats: updatedStats
        )
    }

    func updatingDiskStats(
        from snapshot: SystemDiskSnapshot,
        samples: [Double]
    ) -> PerformanceDevice {
        guard kind == .disk else { return self }

        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Active time":
                PerformanceStat(label: stat.label, value: "\(snapshot.activePercent)%")
            case "Average response time":
                PerformanceStat(label: stat.label, value: formattedMilliseconds(snapshot.averageResponseMilliseconds))
            case "Read speed":
                PerformanceStat(label: stat.label, value: formattedBytesPerSecond(snapshot.readBytesPerSecond))
            case "Write speed":
                PerformanceStat(label: stat.label, value: formattedBytesPerSecond(snapshot.writeBytesPerSecond))
            case "Capacity":
                PerformanceStat(label: stat.label, value: snapshot.capacityBytes > 0 ? formattedGigabytes(snapshot.capacityBytes) : "--")
            case "Type":
                PerformanceStat(label: stat.label, value: snapshot.type)
            default:
                stat
            }
        }

        let totalTransferBytes = snapshot.readBytesPerSecond + snapshot.writeBytesPerSecond

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: snapshot.type,
            valueText: "\(snapshot.activePercent)%",
            detailTitle: detailTitle,
            detailSubtitle: snapshot.name,
            color: color,
            samples: samples.isEmpty ? [0] : samples,
            stats: updatedStats + [
                PerformanceStat(label: "Disk transfer rate", value: formattedBytesPerSecond(totalTransferBytes))
            ]
        )
    }

    func updatingNetworkStats(
        from snapshot: SystemNetworkSnapshot,
        samples: [Double]
    ) -> PerformanceDevice {
        guard kind == .ethernet else { return self }

        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Send":
                PerformanceStat(label: stat.label, value: formattedNetworkRate(snapshot.sentBytesPerSecond))
            case "Receive":
                PerformanceStat(label: stat.label, value: formattedNetworkRate(snapshot.receivedBytesPerSecond))
            case "Adapter name":
                PerformanceStat(label: stat.label, value: snapshot.adapterName)
            case "DNS name":
                PerformanceStat(label: stat.label, value: snapshot.dnsName)
            case "Connection type":
                PerformanceStat(label: stat.label, value: snapshot.connectionType)
            case "IPv4 address":
                PerformanceStat(label: stat.label, value: snapshot.ipv4Address)
            case "RSSI":
                PerformanceStat(label: stat.label, value: formattedDecibelsMilliwatt(snapshot.wifiRSSI))
            case "Noise":
                PerformanceStat(label: stat.label, value: formattedDecibelsMilliwatt(snapshot.wifiNoise))
            case "Channel":
                PerformanceStat(label: stat.label, value: formattedWiFiChannel(snapshot))
            case "Frequency":
                PerformanceStat(label: stat.label, value: snapshot.wifiFrequency ?? "--")
            default:
                stat
            }
        }

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: snapshot.connectionType == "Wi-Fi" ? "Wi-Fi" : title,
            subtitle: snapshot.interfaceName,
            valueText: "S: \(formattedNetworkRate(snapshot.sentBytesPerSecond)) R: \(formattedNetworkRate(snapshot.receivedBytesPerSecond))",
            detailTitle: snapshot.connectionType == "Wi-Fi" ? "Wi-Fi" : detailTitle,
            detailSubtitle: snapshot.adapterName,
            color: color,
            samples: normalizedNetworkSamples(samples),
            stats: updatedStats
        )
    }

    func updatingNPUStats(
        from snapshot: SystemNPUSnapshot,
        samples: [Double]
    ) -> PerformanceDevice {
        guard kind == .npu else { return self }

        let utilizationText = snapshot.usagePercent.map { "\($0)%" } ?? "--"
        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Utilization":
                PerformanceStat(label: stat.label, value: utilizationText)
            case "Cores":
                PerformanceStat(label: stat.label, value: snapshot.coreCount.map(String.init) ?? "--")
            case "Architecture":
                PerformanceStat(label: stat.label, value: snapshot.architecture)
            case "Version":
                PerformanceStat(label: stat.label, value: snapshot.version)
            case "Board type":
                PerformanceStat(label: stat.label, value: snapshot.boardType)
            case "Core ML":
                PerformanceStat(label: stat.label, value: snapshot.computeDeviceState)
            case "Precision":
                PerformanceStat(label: stat.label, value: snapshot.precisionSupport)
            case "Registry class":
                PerformanceStat(label: stat.label, value: snapshot.registryClassName)
            default:
                stat
            }
        }

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: snapshot.name,
            valueText: utilizationText,
            detailTitle: detailTitle,
            detailSubtitle: snapshot.name,
            color: color,
            samples: samples.isEmpty ? [0] : samples,
            stats: updatedStats + [
                PerformanceStat(label: "Matched device", value: snapshot.matchedName)
            ]
        )
    }

    func updatingBatteryStats(
        from snapshot: SystemBatterySnapshot,
        samples: [Double],
        sensorSnapshot: SystemCPUSensorSnapshot
    ) -> PerformanceDevice {
        guard kind == .battery else { return self }

        let adapterText: String
        if let adapterWatts = snapshot.adapterWatts {
            adapterText = "\(snapshot.adapterName) (\(adapterWatts) W)"
        } else {
            adapterText = snapshot.adapterName
        }

        let updatedStats = stats.map { stat in
            switch stat.label {
            case "Power source":
                PerformanceStat(label: stat.label, value: snapshot.powerSource)
            case "Technology":
                PerformanceStat(label: stat.label, value: snapshot.technology)
            case "Temperature":
                PerformanceStat(label: stat.label, value: formattedTemperature(snapshot.temperatureCelsius))
            case "Voltage":
                PerformanceStat(label: stat.label, value: formattedVolts(snapshot.voltageVolts))
            case "Current now":
                PerformanceStat(label: stat.label, value: formattedMilliamps(snapshot.currentMilliamps))
            case "Power now":
                PerformanceStat(label: stat.label, value: formattedWatts(snapshot.powerWatts))
            case "Charge type":
                PerformanceStat(label: stat.label, value: snapshot.chargeType)
            case "Cycles":
                PerformanceStat(label: stat.label, value: snapshot.cycleCount.map(String.init) ?? "--")
            case "Current charge":
                PerformanceStat(label: stat.label, value: formattedMilliampHours(snapshot.currentChargeMilliampHours))
            case "Max charge":
                PerformanceStat(label: stat.label, value: formattedMilliampHours(snapshot.maxChargeMilliampHours))
            case "Level":
                PerformanceStat(label: stat.label, value: "\(snapshot.levelPercent)%")
            case "Time to full":
                PerformanceStat(label: stat.label, value: formattedMinutes(snapshot.timeToFullMinutes))
            case "Adapter":
                PerformanceStat(label: stat.label, value: adapterText)
            case "Package power":
                PerformanceStat(label: stat.label, value: formattedWatts(sensorSnapshot.combinedPowerWatts))
            default:
                stat
            }
        }

        return PerformanceDevice(
            id: id,
            kind: kind,
            title: title,
            subtitle: snapshot.chargeState,
            valueText: "\(snapshot.levelPercent)%",
            detailTitle: detailTitle,
            detailSubtitle: snapshot.name,
            color: color,
            samples: samples.isEmpty ? [Double(snapshot.levelPercent)] : samples,
            stats: updatedStats
        )
    }
}

private func formattedGigabytes(_ bytes: UInt64) -> String {
    let gibibytes = Double(bytes) / (1024 * 1024 * 1024)
    return String(format: "%.1f GB", gibibytes)
}

private func formattedMegabytes(_ bytes: UInt64) -> String {
    let megabytes = Double(bytes) / (1024 * 1024)
    return String(format: "%.0f MB", megabytes)
}

private func formattedSwapUsage(usedBytes: UInt64, totalBytes: UInt64) -> String {
    guard totalBytes > 0 else {
        return "--"
    }

    return "\(formattedGigabytes(usedBytes))/\(formattedGigabytes(totalBytes))"
}

private func formattedBytesPerSecond(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return "\(formatter.string(fromByteCount: Int64(bytes)))/s"
}

private func formattedNetworkRate(_ bytesPerSecond: UInt64) -> String {
    let bitsPerSecond = Double(bytesPerSecond) * 8

    if bitsPerSecond >= 1_000_000_000 {
        return String(format: "%.1f Gbps", bitsPerSecond / 1_000_000_000)
    }

    if bitsPerSecond >= 1_000_000 {
        return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
    }

    if bitsPerSecond >= 1_000 {
        return String(format: "%.0f Kbps", bitsPerSecond / 1_000)
    }

    return "\(Int(bitsPerSecond.rounded())) bps"
}

private func formattedDecibelsMilliwatt(_ value: Int?) -> String {
    guard let value else {
        return "--"
    }

    return "\(value) dBm"
}

private func formattedWiFiChannel(_ snapshot: SystemNetworkSnapshot) -> String {
    guard let channel = snapshot.wifiChannel else {
        return "--"
    }

    let parts = [
        String(channel),
        snapshot.wifiBand,
        snapshot.wifiChannelWidth
    ].compactMap { $0 }.filter { $0 != "--" }

    return parts.joined(separator: " / ")
}

private func normalizedNetworkSamples(_ samples: [Double]) -> [Double] {
    guard let maximum = samples.max(), maximum > 0 else {
        return samples.isEmpty ? [0] : samples
    }

    return samples.map { min(max($0 / maximum * 100, 0), 100) }
}

private extension PerformanceDevice {
    var outlineColor: Color {
        switch kind {
        case .cpu:
            Color(red: 0.32, green: 0.88, blue: 0.96)
        case .memory:
            Color(red: 0.61, green: 0.68, blue: 1.00)
        case .disk:
            Color(red: 0.28, green: 0.82, blue: 0.86)
        case .ethernet:
            Color(red: 1.00, green: 0.56, blue: 0.84)
        case .gpu:
            Color(red: 0.84, green: 0.64, blue: 1.00)
        case .battery:
            Color(red: 0.98, green: 0.72, blue: 0.28)
        case .npu:
            Color(red: 0.34, green: 0.78, blue: 0.59)
        }
    }
}

private func formattedMilliseconds(_ milliseconds: Double) -> String {
    if milliseconds < 10 {
        return String(format: "%.1f ms", milliseconds)
    }

    return "\(Int(milliseconds.rounded())) ms"
}

private func formattedTemperature(_ celsius: Double?) -> String {
    guard let celsius else { return "--" }
    return String(format: "%.1f C", celsius)
}

private func formattedVolts(_ volts: Double?) -> String {
    guard let volts else { return "--" }
    return String(format: "%.3f V", volts)
}

private func formattedMilliamps(_ milliamps: Int?) -> String {
    guard let milliamps else { return "--" }
    return "\(milliamps) mA"
}

private func formattedWatts(_ watts: Double?) -> String {
    guard let watts else { return "--" }
    return String(format: "%.2f W", watts)
}

private func formattedMilliampHours(_ milliampHours: Int?) -> String {
    guard let milliampHours else { return "--" }
    return "\(milliampHours) mAh"
}

private func formattedMinutes(_ minutes: Int?) -> String {
    guard let minutes else { return "--" }

    if minutes < 60 {
        return "\(minutes) min"
    }

    return String(format: "%d h %02d min", minutes / 60, minutes % 60)
}
