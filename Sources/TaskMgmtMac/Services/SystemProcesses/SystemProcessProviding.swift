import Foundation

protocol SystemProcessProviding: Sendable {
    func processes() -> [SystemProcessInfo]
}
