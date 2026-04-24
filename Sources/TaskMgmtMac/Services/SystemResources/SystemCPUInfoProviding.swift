import Foundation

protocol SystemCPUInfoProviding: Sendable {
    func processorName() -> String?
    func processorSpeedText() -> String?
    func systemBootDate() -> Date?
}
