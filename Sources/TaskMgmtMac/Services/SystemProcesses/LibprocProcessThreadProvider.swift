import Darwin
import Foundation

struct LibprocProcessThreadProvider: ProcessThreadProviding {
    private let usageScale = 1000.0
    private let maxThreadListCapacity = 16_384

    func threads(for pid: Int) -> [ProcessThreadInfo] {
        guard pid > 0 else { return [] }

        return threadIDs(for: pid)
            .compactMap { threadInfo(pid: pid, threadID: $0) }
            .sorted { lhs, rhs in
                if lhs.cpuPercent == rhs.cpuPercent {
                    if lhs.currentPriority == rhs.currentPriority {
                        return lhs.threadID < rhs.threadID
                    }
                    return lhs.currentPriority > rhs.currentPriority
                }
                return lhs.cpuPercent > rhs.cpuPercent
            }
    }

    private func threadIDs(for pid: Int) -> [UInt64] {
        var capacity = max(threadCount(for: pid) + 16, 64)

        while capacity <= maxThreadListCapacity {
            var threadIDs = [UInt64](repeating: 0, count: capacity)
            let result = threadIDs.withUnsafeMutableBytes { buffer in
                proc_pidinfo(
                    pid_t(pid),
                    PROC_PIDLISTTHREADS,
                    0,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }

            guard result > 0 else { return [] }

            let count = min(Int(result) / MemoryLayout<UInt64>.stride, threadIDs.count)
            if count < threadIDs.count || capacity == maxThreadListCapacity {
                return Array(threadIDs.prefix(count)).filter { $0 > 0 }
            }

            capacity = min(capacity * 2, maxThreadListCapacity)
        }

        return []
    }

    private func threadCount(for pid: Int) -> Int {
        var taskInfo = proc_taskinfo()
        let taskInfoSize = MemoryLayout<proc_taskinfo>.stride
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: taskInfoSize) { taskInfoPointer in
                proc_pidinfo(
                    pid_t(pid),
                    PROC_PIDTASKINFO,
                    0,
                    taskInfoPointer,
                    Int32(taskInfoSize)
                )
            }
        }

        guard result == taskInfoSize else { return 0 }
        return max(Int(taskInfo.pti_threadnum), 0)
    }

    private func threadInfo(pid: Int, threadID: UInt64) -> ProcessThreadInfo? {
        var threadInfo = proc_threadinfo()
        let threadInfoSize = MemoryLayout<proc_threadinfo>.stride
        let result = withUnsafeMutablePointer(to: &threadInfo) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: threadInfoSize) { threadInfoPointer in
                proc_pidinfo(
                    pid_t(pid),
                    PROC_PIDTHREADINFO,
                    threadID,
                    threadInfoPointer,
                    Int32(threadInfoSize)
                )
            }
        }

        guard result == threadInfoSize else { return nil }

        return ProcessThreadInfo(
            threadID: threadID,
            name: threadName(from: threadInfo),
            cpuPercent: max(Double(threadInfo.pth_cpu_usage) / usageScale * 100, 0),
            state: threadState(from: threadInfo.pth_run_state),
            currentPriority: Int(threadInfo.pth_curpri),
            basePriority: Int(threadInfo.pth_priority),
            maxPriority: Int(threadInfo.pth_maxpriority),
            policy: Int(threadInfo.pth_policy),
            sleepTimeSeconds: Int(threadInfo.pth_sleep_time),
            userTimeNanoseconds: threadInfo.pth_user_time,
            systemTimeNanoseconds: threadInfo.pth_system_time
        )
    }

    private func threadName(from threadInfo: proc_threadinfo) -> String? {
        let name = withUnsafePointer(to: threadInfo.pth_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXTHREADNAMESIZE)) { namePointer in
                String(cString: namePointer)
            }
        }

        return name.isEmpty ? nil : name
    }

    private func threadState(from state: Int32) -> ProcessThreadState {
        switch state {
        case TH_STATE_RUNNING:
            return .running
        case TH_STATE_STOPPED:
            return .stopped
        case TH_STATE_WAITING:
            return .waiting
        case TH_STATE_UNINTERRUPTIBLE:
            return .uninterruptible
        case TH_STATE_HALTED:
            return .halted
        default:
            return .unknown
        }
    }
}
