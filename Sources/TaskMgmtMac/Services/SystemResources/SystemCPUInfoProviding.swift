import Foundation

protocol SystemCPUInfoProviding: Sendable {
    func processorName() -> String?
}
