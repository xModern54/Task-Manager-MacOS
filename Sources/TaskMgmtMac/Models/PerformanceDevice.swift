import SwiftUI

struct PerformanceDevice: Identifiable, Hashable {
    enum Kind: Hashable {
        case cpu
        case memory
        case disk
        case ethernet
        case gpu
        case npu
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let valueText: String
    let detailTitle: String
    let detailSubtitle: String
    let color: Color
    let samples: [Double]
    let stats: [PerformanceStat]

    static let mockDevices: [PerformanceDevice] = [
        PerformanceDevice(
            id: "cpu",
            kind: .cpu,
            title: "CPU",
            subtitle: "",
            valueText: "3% 5.03 GHz",
            detailTitle: "CPU",
            detailSubtitle: "12th Gen Intel(R) Core(TM) i5-13600KF",
            color: Color(red: 0.13, green: 0.78, blue: 0.90),
            samples: [0, 0, 0, 0, 0.2, 0.1, 2, 0.3, 0, 0, 0.6, 0.1, 0, 3, 0.4, 0.2, 0, 0, 0.1, 31],
            stats: [
                PerformanceStat(label: "Utilization", value: "3%"),
                PerformanceStat(label: "Speed", value: "5.03 GHz"),
                PerformanceStat(label: "Processes", value: "78"),
                PerformanceStat(label: "Threads", value: "1741"),
                PerformanceStat(label: "Up time", value: "0:02:11:47")
            ]
        ),
        PerformanceDevice(
            id: "memory",
            kind: .memory,
            title: "Memory",
            subtitle: "",
            valueText: "6.1/31.9 GB (19%)",
            detailTitle: "Memory",
            detailSubtitle: "32.0 GB",
            color: Color(red: 0.48, green: 0.55, blue: 0.94),
            samples: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 19, 19, 19, 19, 20, 19, 19, 19, 19],
            stats: [
                PerformanceStat(label: "In use (Compressed)", value: "6.0 GB (0 MB)"),
                PerformanceStat(label: "Available", value: "25.8 GB"),
                PerformanceStat(label: "Committed", value: "8.3/33.9 GB"),
                PerformanceStat(label: "Cached", value: "2.6 GB"),
                PerformanceStat(label: "Speed", value: "4100 MHz"),
                PerformanceStat(label: "Slots used", value: "2 of 4")
            ]
        ),
        PerformanceDevice(
            id: "disk0",
            kind: .disk,
            title: "Disk 0",
            subtitle: "Internal SSD",
            valueText: "0%",
            detailTitle: "Disk 0",
            detailSubtitle: "MacBook Internal SSD",
            color: Color(red: 0.16, green: 0.70, blue: 0.73),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Active time", value: "0%"),
                PerformanceStat(label: "Average response time", value: "0 ms"),
                PerformanceStat(label: "Read speed", value: "0 KB/s"),
                PerformanceStat(label: "Write speed", value: "0 KB/s"),
                PerformanceStat(label: "Capacity", value: "--"),
                PerformanceStat(label: "Type", value: "SSD")
            ]
        ),
        PerformanceDevice(
            id: "ethernet",
            kind: .ethernet,
            title: "Network",
            subtitle: "--",
            valueText: "S: 0 bps R: 0 bps",
            detailTitle: "Network",
            detailSubtitle: "--",
            color: Color(red: 0.92, green: 0.45, blue: 0.76),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Send", value: "0 bps"),
                PerformanceStat(label: "Receive", value: "0 bps"),
                PerformanceStat(label: "Adapter name", value: "--"),
                PerformanceStat(label: "DNS name", value: "--"),
                PerformanceStat(label: "Connection type", value: "--"),
                PerformanceStat(label: "IPv4 address", value: "--")
            ]
        ),
        PerformanceDevice(
            id: "gpu0",
            kind: .gpu,
            title: "GPU 0",
            subtitle: "GPU",
            valueText: "0%",
            detailTitle: "GPU",
            detailSubtitle: "GPU",
            color: Color(red: 0.73, green: 0.52, blue: 0.91),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Utilization", value: "0%"),
                PerformanceStat(label: "GPU memory", value: "--"),
                PerformanceStat(label: "Allocated memory", value: "--"),
                PerformanceStat(label: "Memory type", value: "--"),
                PerformanceStat(label: "GPU cores", value: "--")
            ]
        ),
        PerformanceDevice(
            id: "npu0",
            kind: .npu,
            title: "NPU 0",
            subtitle: "Neural Engine",
            valueText: "--",
            detailTitle: "NPU",
            detailSubtitle: "Apple Neural Engine",
            color: Color(red: 0.21, green: 0.66, blue: 0.48),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Utilization", value: "--"),
                PerformanceStat(label: "Cores", value: "--"),
                PerformanceStat(label: "Architecture", value: "--"),
                PerformanceStat(label: "Version", value: "--"),
                PerformanceStat(label: "Board type", value: "--"),
                PerformanceStat(label: "Core ML", value: "--"),
                PerformanceStat(label: "Precision", value: "Core ML managed"),
                PerformanceStat(label: "Registry class", value: "--")
            ]
        )
    ]
}

struct PerformanceStat: Hashable {
    let label: String
    let value: String
}
