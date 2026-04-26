import Foundation

struct ProcessMetric: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case apps = "Apps"
        case backgroundProcesses = "Background processes"
    }

    let name: String
    let iconSystemName: String
    let executablePath: String?
    let group: Group
    let childCount: Int?
    let status: ProcessStatus?
    let cpu: Double
    let memoryMB: Double
    let diskMBs: Double
    let networkMbps: Double
    let powerUsage: PowerUsage
    let gpu: Double
    let pid: Int

    var id: Int { pid }

    init(
        name: String,
        iconSystemName: String,
        executablePath: String? = nil,
        group: Group,
        childCount: Int? = nil,
        status: ProcessStatus? = nil,
        cpu: Double,
        memoryMB: Double,
        diskMBs: Double,
        networkMbps: Double,
        powerUsage: PowerUsage,
        gpu: Double,
        pid: Int
    ) {
        self.name = name
        self.iconSystemName = iconSystemName
        self.executablePath = executablePath
        self.group = group
        self.childCount = childCount
        self.status = status
        self.cpu = cpu
        self.memoryMB = memoryMB
        self.diskMBs = diskMBs
        self.networkMbps = networkMbps
        self.powerUsage = powerUsage
        self.gpu = gpu
        self.pid = pid
    }
}

enum ProcessStatus: Hashable, Sendable {
    case suspended
    case efficiency
}

enum PowerUsage: String, Hashable, Sendable {
    case veryLow = "Very low"
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

struct ProcessSummary: Hashable, Sendable {
    let cpu: Int
    let memory: Int
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let memoryCompressedBytes: UInt64
    let disk: Int
    let network: Int
    let gpu: Int
    let processCount: Int
    let threadCount: Int

    init(
        cpu: Int,
        memory: Int,
        memoryUsedBytes: UInt64 = 0,
        memoryTotalBytes: UInt64 = 0,
        memoryCompressedBytes: UInt64 = 0,
        disk: Int,
        network: Int,
        gpu: Int,
        processCount: Int,
        threadCount: Int
    ) {
        self.cpu = cpu
        self.memory = memory
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryCompressedBytes = memoryCompressedBytes
        self.disk = disk
        self.network = network
        self.gpu = gpu
        self.processCount = processCount
        self.threadCount = threadCount
    }
}

struct ProcessSnapshot: Hashable, Sendable {
    let summary: ProcessSummary
    let processes: [ProcessMetric]
}
