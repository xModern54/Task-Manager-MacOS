import Darwin
import Foundation

struct LibprocSystemProcessProvider: SystemProcessProviding {
    func processes() -> [SystemProcessInfo] {
        let pidBufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard pidBufferSize > 0 else { return [] }
        let timebase = machTimebase()

        let pidCapacity = Int(pidBufferSize) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: pidCapacity)

        let bytesWritten = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard bytesWritten > 0 else { return [] }

        let actualCount = min(Int(bytesWritten) / MemoryLayout<pid_t>.stride, pids.count)

        return pids.prefix(actualCount)
            .compactMap { processInfo(for: $0, timebase: timebase) }
            .sorted { lhs, rhs in
                if lhs.residentMemoryBytes == rhs.residentMemoryBytes {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.residentMemoryBytes > rhs.residentMemoryBytes
            }
    }

    private func processInfo(for pid: pid_t, timebase: MachTimebase) -> SystemProcessInfo? {
        guard pid > 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let taskInfoSize = MemoryLayout<proc_taskinfo>.stride
        let taskInfoResult = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: taskInfoSize) { taskInfoPointer in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, taskInfoPointer, Int32(taskInfoSize))
            }
        }
        guard taskInfoResult == taskInfoSize else { return nil }

        let name = processName(for: pid)
        guard !name.isEmpty else { return nil }

        return SystemProcessInfo(
            pid: Int(pid),
            name: name,
            executablePath: executablePath(for: pid),
            cpuTimeNanoseconds: nanoseconds(forMachTicks: taskInfo.pti_total_user + taskInfo.pti_total_system, timebase: timebase),
            residentMemoryBytes: taskInfo.pti_resident_size,
            physicalFootprintBytes: taskInfo.pti_resident_size
        )
    }

    private func processName(for pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return "" }

        let bytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func executablePath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return nil }

        let bytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let path = String(decoding: bytes, as: UTF8.self)
        return path.isEmpty ? nil : path
    }

    private func machTimebase() -> MachTimebase {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return MachTimebase(numer: UInt64(info.numer), denom: UInt64(max(info.denom, 1)))
    }

    private func nanoseconds(forMachTicks ticks: UInt64, timebase: MachTimebase) -> UInt64 {
        UInt64((Double(ticks) * Double(timebase.numer) / Double(timebase.denom)).rounded())
    }
}

private struct MachTimebase {
    let numer: UInt64
    let denom: UInt64
}
