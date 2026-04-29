import Foundation

protocol StartupItemProviding: Sendable {
    func startupItems() async -> [StartupItem]
}
