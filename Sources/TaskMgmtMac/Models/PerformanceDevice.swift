import SwiftUI

struct PerformanceDevice: Identifiable, Hashable {
    enum Kind: Hashable {
        case cpu
        case memory
        case disk
        case ethernet
        case gpu
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
            title: "Disk 0 (E:)",
            subtitle: "HDD",
            valueText: "0%",
            detailTitle: "Disk 0 (E:)",
            detailSubtitle: "TOSHIBA HDWD110",
            color: Color(red: 0.16, green: 0.70, blue: 0.73),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Active time", value: "0%"),
                PerformanceStat(label: "Average response time", value: "0 ms"),
                PerformanceStat(label: "Read speed", value: "0 KB/s"),
                PerformanceStat(label: "Write speed", value: "0 KB/s"),
                PerformanceStat(label: "Capacity", value: "932 GB"),
                PerformanceStat(label: "Type", value: "HDD")
            ]
        ),
        PerformanceDevice(
            id: "disk1",
            kind: .disk,
            title: "Disk 1 (C:)",
            subtitle: "SSD",
            valueText: "0%",
            detailTitle: "Disk 1 (C:)",
            detailSubtitle: "NVMe SSD",
            color: Color(red: 0.16, green: 0.70, blue: 0.73),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Active time", value: "0%"),
                PerformanceStat(label: "Average response time", value: "0 ms"),
                PerformanceStat(label: "Read speed", value: "0 KB/s"),
                PerformanceStat(label: "Write speed", value: "0 KB/s"),
                PerformanceStat(label: "Capacity", value: "1024 GB"),
                PerformanceStat(label: "Type", value: "SSD")
            ]
        ),
        PerformanceDevice(
            id: "disk2",
            kind: .disk,
            title: "Disk 2 (D:)",
            subtitle: "SSD",
            valueText: "0%",
            detailTitle: "Disk 2 (D:)",
            detailSubtitle: "SATA SSD",
            color: Color(red: 0.16, green: 0.70, blue: 0.73),
            samples: Array(repeating: 0, count: 20),
            stats: [
                PerformanceStat(label: "Active time", value: "0%"),
                PerformanceStat(label: "Average response time", value: "0 ms"),
                PerformanceStat(label: "Read speed", value: "0 KB/s"),
                PerformanceStat(label: "Write speed", value: "0 KB/s"),
                PerformanceStat(label: "Capacity", value: "512 GB"),
                PerformanceStat(label: "Type", value: "SSD")
            ]
        ),
        PerformanceDevice(
            id: "ethernet",
            kind: .ethernet,
            title: "Ethernet",
            subtitle: "Ethernet",
            valueText: "S: 0 R: 8.0 Kbps",
            detailTitle: "Ethernet",
            detailSubtitle: "Realtek Gaming 2.5GbE Family Controller",
            color: Color(red: 0.92, green: 0.45, blue: 0.76),
            samples: [0, 0, 0, 0, 0, 0, 1, 0, 0, 4, 15, 92, 0, 0, 8, 0, 0, 95, 6, 2],
            stats: [
                PerformanceStat(label: "Send", value: "0 Kbps"),
                PerformanceStat(label: "Receive", value: "8.0 Kbps"),
                PerformanceStat(label: "Adapter name", value: "Ethernet"),
                PerformanceStat(label: "DNS name", value: "lan"),
                PerformanceStat(label: "Connection type", value: "Ethernet"),
                PerformanceStat(label: "IPv4 address", value: "192.168.1.219")
            ]
        ),
        PerformanceDevice(
            id: "gpu0",
            kind: .gpu,
            title: "GPU 0",
            subtitle: "NVIDIA GeForce RTX 5070 Ti",
            valueText: "3% (41 C)",
            detailTitle: "GPU",
            detailSubtitle: "NVIDIA GeForce RTX 5070 Ti",
            color: Color(red: 0.73, green: 0.52, blue: 0.91),
            samples: [0, 0, 55, 0, 0, 0, 0, 1, 0, 2, 0, 0, 0, 4, 0, 0, 1, 0, 2, 3],
            stats: [
                PerformanceStat(label: "Utilization", value: "3%"),
                PerformanceStat(label: "Dedicated GPU memory", value: "0.6/16.0 GB"),
                PerformanceStat(label: "GPU Memory", value: "0.7/31.9 GB"),
                PerformanceStat(label: "Shared GPU memory", value: "0.1/15.9 GB"),
                PerformanceStat(label: "GPU Temperature", value: "41 C"),
                PerformanceStat(label: "Driver version", value: "32.0.15.6094")
            ]
        )
    ]
}

struct PerformanceStat: Hashable {
    let label: String
    let value: String
}
