import Foundation

protocol SystemMemoryProviding: Sendable {
    func usagePercent() -> Int
}
