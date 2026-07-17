import Foundation

protocol SystemCPUInfoProviding: Sendable {
    func processorName() -> String?
    func processorSpeedText() -> String?
    func performanceCoreSpeedLabel() -> String
    func systemBootDate() -> Date?
}
