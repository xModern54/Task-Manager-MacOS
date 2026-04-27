import Foundation

protocol SystemNetworkInfoProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemNetworkSnapshot
}

struct SystemNetworkSnapshot: Sendable {
    let interfaceName: String
    let adapterName: String
    let connectionType: String
    let dnsName: String
    let ipv4Address: String
    let sentBytesPerSecond: UInt64
    let receivedBytesPerSecond: UInt64
    let wifiRSSI: Int?
    let wifiNoise: Int?
    let wifiChannel: Int?
    let wifiBand: String?
    let wifiChannelWidth: String?
    let wifiFrequency: String?

    var throughputBytesPerSecond: UInt64 {
        sentBytesPerSecond + receivedBytesPerSecond
    }

    static let unavailable = SystemNetworkSnapshot(
        interfaceName: "--",
        adapterName: "Network",
        connectionType: "--",
        dnsName: "--",
        ipv4Address: "--",
        sentBytesPerSecond: 0,
        receivedBytesPerSecond: 0,
        wifiRSSI: nil,
        wifiNoise: nil,
        wifiChannel: nil,
        wifiBand: nil,
        wifiChannelWidth: nil,
        wifiFrequency: nil
    )
}
