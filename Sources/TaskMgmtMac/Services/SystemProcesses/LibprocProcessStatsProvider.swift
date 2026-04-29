import Darwin
import Foundation

struct LibprocProcessStatsProvider: ProcessStatsProviding {
    func snapshot(for pid: Int) -> ProcessStatsSnapshot? {
        guard pid > 0 else { return nil }
        guard let taskInfo = taskAllInfo(for: pid) else { return nil }

        let timebase = machTimebase()
        let userTime = nanoseconds(forMachTicks: taskInfo.ptinfo.pti_total_user, timebase: timebase)
        let systemTime = nanoseconds(forMachTicks: taskInfo.ptinfo.pti_total_system, timebase: timebase)

        return ProcessStatsSnapshot(
            timestampNanoseconds: DispatchTime.now().uptimeNanoseconds,
            activeProcessorCount: max(ProcessInfo.processInfo.activeProcessorCount, 1),
            cpuTimeNanoseconds: userTime + systemTime,
            userTimeNanoseconds: userTime,
            systemTimeNanoseconds: systemTime,
            residentBytes: taskInfo.ptinfo.pti_resident_size,
            virtualBytes: taskInfo.ptinfo.pti_virtual_size,
            threadCount: Int(taskInfo.ptinfo.pti_threadnum),
            runningThreadCount: Int(taskInfo.ptinfo.pti_numrunning),
            priority: Int(taskInfo.ptinfo.pti_priority),
            policy: Int(taskInfo.ptinfo.pti_policy),
            niceValue: Int(taskInfo.pbsd.pbi_nice),
            openFileCount: Int(taskInfo.pbsd.pbi_nfiles),
            pageFaults: Int(taskInfo.ptinfo.pti_faults),
            pageIns: Int(taskInfo.ptinfo.pti_pageins),
            copyOnWriteFaults: Int(taskInfo.ptinfo.pti_cow_faults),
            machMessagesSent: Int(taskInfo.ptinfo.pti_messages_sent),
            machMessagesReceived: Int(taskInfo.ptinfo.pti_messages_received),
            machSyscalls: Int(taskInfo.ptinfo.pti_syscalls_mach),
            unixSyscalls: Int(taskInfo.ptinfo.pti_syscalls_unix),
            contextSwitches: Int(taskInfo.ptinfo.pti_csw)
        )
    }

    private func taskAllInfo(for pid: Int) -> proc_taskallinfo? {
        var taskInfo = proc_taskallinfo()
        let taskInfoSize = MemoryLayout<proc_taskallinfo>.stride
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: taskInfoSize) { taskInfoPointer in
                proc_pidinfo(
                    pid_t(pid),
                    PROC_PIDTASKALLINFO,
                    0,
                    taskInfoPointer,
                    Int32(taskInfoSize)
                )
            }
        }

        guard result == taskInfoSize else { return nil }
        return taskInfo
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
