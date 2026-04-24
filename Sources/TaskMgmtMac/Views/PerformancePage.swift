import SwiftUI

struct PerformancePage: View {
    let summary: ProcessSummary
    let cpuHistory: [Double]

    @State private var selectedDeviceID = PerformanceDevice.mockDevices[0].id
    @State private var processorName: String?
    @State private var processorSpeedText: String?
    @State private var systemBootDate: Date?
    @State private var didLoadProcessorName = false

    private let cpuInfoProvider: any SystemCPUInfoProviding = SysctlCPUInfoProvider()

    private var devices: [PerformanceDevice] {
        PerformanceDevice.mockDevices.map { device in
            device.kind == .cpu
                ? device.updatingCPUStats(
                    from: summary,
                    samples: cpuHistory,
                    speedText: processorSpeedText ?? "--",
                    uptimeText: uptimeText
                )
                : device
        }
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
            VStack(spacing: 6) {
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
            .padding(.horizontal, 10)
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
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(isSelected ? WindowsTaskManagerTheme.tableSelection : Color.clear)
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
            }
        }
        .padding(.top, 16)
        .padding(.trailing, 14)
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
            LabeledGraph(title: "Memory usage", trailing: "31.9 GB", device: device, height: 205, fill: true)

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
            LabeledGraph(title: "Throughput", trailing: "500 Kbps", device: device, height: 340, fill: true)
            StatGrid(stats: device.stats, columns: 2)
        }
    }
}

private struct GPUPerformanceDetail: View {
    let device: PerformanceDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 8) {
                LabeledGraph(title: "3D", trailing: "1%", device: device, height: 82, fill: true)
                LabeledGraph(title: "Copy", trailing: "2%", device: device, height: 82, fill: true)
                LabeledGraph(title: "Video Encode", trailing: "0%", device: device, height: 82, fill: true)
                LabeledGraph(title: "Video Decode", trailing: "3%", device: device, height: 82, fill: true)
            }

            LabeledGraph(title: "Dedicated GPU memory usage", trailing: "16.0 GB", device: device, height: 68)
            LabeledGraph(title: "Shared GPU memory usage", trailing: "15.9 GB", device: device, height: 68)
            StatGrid(stats: device.stats, columns: 3)
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
        speedText: String,
        uptimeText: String
    ) -> PerformanceDevice {
        guard kind == .cpu else { return self }

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
            stats: updatedStats
        )
    }
}
