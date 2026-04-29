import Foundation

protocol ProcessStatsProviding: Sendable {
    func snapshot(for pid: Int) -> ProcessStatsSnapshot?
}
