import Darwin
import Foundation

struct LibprocProcessModuleProvider: ProcessModuleProviding {
    private let maxRegionCount = 50_000

    func modules(for pid: Int, executablePath: String?) -> [ProcessModuleInfo] {
        guard pid > 0 else { return [] }

        let pageSize = UInt64(max(getpagesize(), 1))
        var address: UInt64 = 1
        var modules: [String: ModuleAccumulator] = [:]

        for _ in 0..<maxRegionCount {
            guard let region = regionInfo(pid: pid, address: address) else {
                break
            }

            let regionAddress = region.prp_prinfo.pri_address
            let regionSize = region.prp_prinfo.pri_size
            guard regionSize > 0 else { break }

            let path = pathString(from: region)
            if !path.isEmpty {
                var accumulator = modules[path] ?? ModuleAccumulator(
                    path: path,
                    executablePath: executablePath
                )
                accumulator.add(region: region, pageSize: pageSize)
                modules[path] = accumulator
            }

            let nextAddress = regionAddress &+ regionSize
            guard nextAddress > address else { break }
            address = nextAddress
        }

        return modules.values
            .map(\.module)
            .sorted { lhs, rhs in
                if lhs.residentBytes == rhs.residentBytes {
                    if lhs.mappedBytes == rhs.mappedBytes {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.mappedBytes > rhs.mappedBytes
                }
                return lhs.residentBytes > rhs.residentBytes
            }
    }

    private func regionInfo(pid: Int, address: UInt64) -> proc_regionwithpathinfo? {
        var region = proc_regionwithpathinfo()
        let regionSize = MemoryLayout<proc_regionwithpathinfo>.stride
        let result = withUnsafeMutablePointer(to: &region) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: regionSize) { regionPointer in
                proc_pidinfo(
                    pid_t(pid),
                    PROC_PIDREGIONPATHINFO,
                    address,
                    regionPointer,
                    Int32(regionSize)
                )
            }
        }

        guard result == regionSize else { return nil }
        return region
    }

    private func pathString(from region: proc_regionwithpathinfo) -> String {
        withUnsafePointer(to: region.prp_vip.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { pathPointer in
                String(cString: pathPointer)
            }
        }
    }
}

private struct ModuleAccumulator {
    let path: String
    let executablePath: String?
    var mappedBytes: UInt64 = 0
    var residentBytes: UInt64 = 0
    var privateResidentBytes: UInt64 = 0
    var sharedResidentBytes: UInt64 = 0
    var diskBytes: UInt64?
    var regionCount = 0
    var protections: Set<String> = []

    init(path: String, executablePath: String?) {
        self.path = path
        self.executablePath = executablePath
    }

    mutating func add(region: proc_regionwithpathinfo, pageSize: UInt64) {
        mappedBytes += region.prp_prinfo.pri_size
        residentBytes += UInt64(region.prp_prinfo.pri_pages_resident) * pageSize
        privateResidentBytes += UInt64(region.prp_prinfo.pri_private_pages_resident) * pageSize
        sharedResidentBytes += UInt64(region.prp_prinfo.pri_shared_pages_resident) * pageSize
        diskBytes = max(diskBytes ?? 0, UInt64(max(region.prp_vip.vip_vi.vi_stat.vst_size, 0)))
        regionCount += 1
        protections.insert(protectionString(region.prp_prinfo.pri_protection))
    }

    var module: ProcessModuleInfo {
        ProcessModuleInfo(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            kind: kind,
            mappedBytes: mappedBytes,
            residentBytes: residentBytes,
            privateResidentBytes: privateResidentBytes,
            sharedResidentBytes: sharedResidentBytes,
            diskBytes: diskBytes,
            regionCount: regionCount,
            protectionSummary: protections.sorted().joined(separator: ", ")
        )
    }

    private var kind: ProcessModuleKind {
        if path == executablePath {
            return .executable
        }

        if path.contains(".framework/") || path.hasSuffix(".framework") {
            return .framework
        }

        if path.hasSuffix(".dylib") || path.hasSuffix(".so") {
            return .dynamicLibrary
        }

        if path.hasSuffix(".bundle") || path.contains(".bundle/") {
            return .bundle
        }

        return .mappedFile
    }

    private func protectionString(_ protection: UInt32) -> String {
        let read = (protection & UInt32(VM_PROT_READ)) != 0 ? "r" : "-"
        let write = (protection & UInt32(VM_PROT_WRITE)) != 0 ? "w" : "-"
        let execute = (protection & UInt32(VM_PROT_EXECUTE)) != 0 ? "x" : "-"
        return read + write + execute
    }
}
