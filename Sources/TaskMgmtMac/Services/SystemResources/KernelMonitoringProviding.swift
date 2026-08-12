import Foundation

protocol KernelMonitoringProviding: Sendable {
    func snapshot() async -> KernelSnapshot
}
