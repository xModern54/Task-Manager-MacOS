import Foundation

protocol ProcessThreadProviding: Sendable {
    func threads(for pid: Int) -> [ProcessThreadInfo]
}
