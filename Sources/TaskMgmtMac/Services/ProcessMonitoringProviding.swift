import Foundation

protocol ProcessMonitoringProviding: Sendable {
    func currentSnapshot(includesProcesses: Bool) async -> ProcessSnapshot
}
