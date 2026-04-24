import Foundation

protocol ProcessMonitoringProviding: Sendable {
    func currentSnapshot() async -> ProcessSnapshot
}
