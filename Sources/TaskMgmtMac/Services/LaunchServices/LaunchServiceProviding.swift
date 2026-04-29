import Foundation

protocol LaunchServiceProviding: Sendable {
    func services() async -> [LaunchServiceItem]
}
