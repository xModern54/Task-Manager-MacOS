import Darwin
import CoreWLAN
import Foundation
import SystemConfiguration

actor SystemConfigurationNetworkInfoProvider: SystemNetworkInfoProviding {
    private var previousCounters: NetworkCounters?
    private var cachedDetails = NetworkDetails.unavailable

    func snapshot(includeDetails: Bool) async -> SystemNetworkSnapshot {
        let sample = await Task.detached(priority: .utility) {
            Self.networkSample(includeDetails: includeDetails)
        }.value

        let liveMetrics = liveMetrics(from: sample)
        if let counters = sample.counters {
            if let previousCounters {
                if counters.timestampNanoseconds >= previousCounters.timestampNanoseconds {
                    self.previousCounters = counters
                }
            } else {
                previousCounters = counters
            }
        }

        cachedDetails = sample.details ?? cachedDetails

        return SystemNetworkSnapshot(
            interfaceName: cachedDetails.interfaceName,
            adapterName: cachedDetails.adapterName,
            connectionType: cachedDetails.connectionType,
            dnsName: cachedDetails.dnsName,
            ipv4Address: cachedDetails.ipv4Address,
            sentBytesPerSecond: liveMetrics.sentBytesPerSecond,
            receivedBytesPerSecond: liveMetrics.receivedBytesPerSecond,
            wifiRSSI: cachedDetails.wifiRSSI,
            wifiNoise: cachedDetails.wifiNoise,
            wifiChannel: cachedDetails.wifiChannel,
            wifiBand: cachedDetails.wifiBand,
            wifiChannelWidth: cachedDetails.wifiChannelWidth,
            wifiFrequency: cachedDetails.wifiFrequency
        )
    }

    private func liveMetrics(from sample: NetworkSample) -> NetworkLiveMetrics {
        guard let current = sample.counters else {
            return .empty
        }

        guard let previousCounters else {
            return .empty
        }

        guard previousCounters.interfaceName == current.interfaceName else {
            return .empty
        }

        guard current.timestampNanoseconds > previousCounters.timestampNanoseconds else {
            return .empty
        }

        let elapsedSeconds = max(Double(current.timestampNanoseconds - previousCounters.timestampNanoseconds) / 1_000_000_000, 0)
        guard elapsedSeconds > 0 else {
            return .empty
        }

        let sentDelta = delta(current.sentBytes, previousCounters.sentBytes)
        let receivedDelta = delta(current.receivedBytes, previousCounters.receivedBytes)

        return NetworkLiveMetrics(
            sentBytesPerSecond: UInt64(Double(sentDelta) / elapsedSeconds),
            receivedBytesPerSecond: UInt64(Double(receivedDelta) / elapsedSeconds)
        )
    }

    private static func networkSample(includeDetails: Bool) -> NetworkSample {
        guard let store = SCDynamicStoreCreate(nil, "TaskMgmtMacNetworkInfo" as CFString, nil, nil),
              let primary = primaryInterfaceInfo(store: store) else {
            return NetworkSample(counters: nil, details: .unavailable)
        }

        let timestamp = DispatchTime.now().uptimeNanoseconds
        let interfaceCounters = interfaceCounters()
        let activeWiFiInterfaceName = activeWiFiInterfaceName()
        let selectedInterfaceName = activeWiFiInterfaceName ?? primary.interfaceName
        let selectedWiFiDetails: WiFiDetails?
        if includeDetails, let activeWiFiInterfaceName {
            selectedWiFiDetails = wifiDetails(interfaceName: activeWiFiInterfaceName)
        } else {
            selectedWiFiDetails = nil
        }
        let counters = interfaceCounters[selectedInterfaceName]
        let networkCounters = counters.map {
            NetworkCounters(
                timestampNanoseconds: timestamp,
                interfaceName: selectedInterfaceName,
                sentBytes: $0.sentBytes,
                receivedBytes: $0.receivedBytes
            )
        }

        let serviceName = configuredServiceName(store: store, serviceID: primary.serviceID)
        let isWiFiSelected = activeWiFiInterfaceName != nil
        let selectedServiceName = isWiFiSelected ? configuredServiceName(store: store, interfaceName: selectedInterfaceName) ?? "Wi-Fi" : serviceName
        let selectedServiceID = isWiFiSelected ? configuredServiceID(store: store, interfaceName: selectedInterfaceName) ?? primary.serviceID : primary.serviceID
        let dns = includeDetails ? dnsInfo(store: store, serviceID: selectedServiceID) : ("--", [])
        let details = NetworkDetails(
            interfaceName: selectedInterfaceName,
            adapterName: selectedServiceName ?? selectedInterfaceName,
            connectionType: isWiFiSelected ? "Wi-Fi" : connectionType(for: selectedInterfaceName, serviceName: serviceName),
            dnsName: dns.0,
            ipv4Address: counters?.ipv4Address ?? "--",
            wifiRSSI: selectedWiFiDetails?.rssi,
            wifiNoise: selectedWiFiDetails?.noise,
            wifiChannel: selectedWiFiDetails?.channel,
            wifiBand: selectedWiFiDetails?.band,
            wifiChannelWidth: selectedWiFiDetails?.width,
            wifiFrequency: selectedWiFiDetails?.frequency
        )

        return NetworkSample(counters: networkCounters, details: details)
    }

    private static func primaryInterfaceInfo(store: SCDynamicStore) -> (interfaceName: String, serviceID: String?)? {
        guard let globalIPv4 = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any],
              let interfaceName = globalIPv4["PrimaryInterface"] as? String else {
            return nil
        }

        return (interfaceName, globalIPv4["PrimaryService"] as? String)
    }

    private static func dnsInfo(store: SCDynamicStore, serviceID: String?) -> (name: String, servers: [String]) {
        let keys = [
            serviceID.map { "State:/Network/Service/\($0)/DNS" },
            "State:/Network/Global/DNS"
        ].compactMap { $0 }

        for key in keys {
            guard let dns = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
                continue
            }

            let domainName = dns["DomainName"] as? String
            let searchDomains = dns["SearchDomains"] as? [String] ?? []
            let serverAddresses = dns["ServerAddresses"] as? [String] ?? []

            if domainName != nil || !searchDomains.isEmpty || !serverAddresses.isEmpty {
                return (domainName ?? searchDomains.first ?? "--", serverAddresses)
            }
        }

        return ("--", [])
    }

    private static func configuredServiceName(store: SCDynamicStore, serviceID: String?) -> String? {
        guard let serviceID,
              let service = SCDynamicStoreCopyValue(
                store,
                "Setup:/Network/Service/\(serviceID)" as CFString
              ) as? [String: Any] else {
            return nil
        }

        return service["UserDefinedName"] as? String
    }

    private static func configuredServiceID(store: SCDynamicStore, interfaceName: String) -> String? {
        guard let keys = SCDynamicStoreCopyKeyList(store, "Setup:/Network/Service/.*/Interface" as CFString) as? [String] else {
            return nil
        }

        for key in keys {
            guard let interface = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  interface["DeviceName"] as? String == interfaceName else {
                continue
            }

            let components = key.components(separatedBy: "/")
            guard let serviceIndex = components.firstIndex(of: "Service"),
                  components.indices.contains(serviceIndex + 1) else {
                continue
            }

            return components[serviceIndex + 1]
        }

        return nil
    }

    private static func configuredServiceName(store: SCDynamicStore, interfaceName: String) -> String? {
        configuredServiceName(store: store, serviceID: configuredServiceID(store: store, interfaceName: interfaceName))
    }

    private static func connectionType(for interfaceName: String, serviceName: String?) -> String {
        if let serviceName, !serviceName.isEmpty {
            return serviceName
        }

        if interfaceName.hasPrefix("utun") {
            return "Tunnel"
        }

        if interfaceName.hasPrefix("en") {
            return "Ethernet/Wi-Fi"
        }

        return interfaceName
    }

    private static func activeWiFiInterfaceName() -> String? {
        guard let interfaces = CWWiFiClient.shared().interfaces() else {
            return nil
        }

        for interface in interfaces {
            guard interface.powerOn(),
                  interface.rssiValue() != 0,
                  let interfaceName = interface.interfaceName else {
                continue
            }

            return interfaceName
        }

        return nil
    }

    private static func wifiDetails(interfaceName: String) -> WiFiDetails? {
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName) else {
            return nil
        }

        let channel = interface.wlanChannel()
        return WiFiDetails(
            interfaceName: interfaceName,
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            channel: channel?.channelNumber,
            band: channel.map { bandText($0.channelBand) },
            width: channel.map { channelWidthText($0.channelWidth) },
            frequency: channel.map { frequencyText(channelNumber: $0.channelNumber, band: $0.channelBand) }
        )
    }

    private static func bandText(_ band: CWChannelBand) -> String {
        switch band {
        case .band2GHz:
            "2.4 GHz"
        case .band5GHz:
            "5 GHz"
        case .band6GHz:
            "6 GHz"
        default:
            "--"
        }
    }

    private static func channelWidthText(_ width: CWChannelWidth) -> String {
        switch width {
        case .width20MHz:
            "20 MHz"
        case .width40MHz:
            "40 MHz"
        case .width80MHz:
            "80 MHz"
        case .width160MHz:
            "160 MHz"
        default:
            "--"
        }
    }

    private static func frequencyText(channelNumber: Int, band: CWChannelBand) -> String {
        let megahertz: Int
        switch band {
        case .band2GHz:
            megahertz = channelNumber == 14 ? 2484 : 2407 + channelNumber * 5
        case .band5GHz:
            megahertz = 5000 + channelNumber * 5
        case .band6GHz:
            megahertz = 5950 + channelNumber * 5
        default:
            return "--"
        }

        return "\(megahertz) MHz"
    }

    private static func interfaceCounters() -> [String: InterfaceSnapshot] {
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPointer) == 0, let first = ifaddrsPointer else {
            return [:]
        }

        defer {
            freeifaddrs(first)
        }

        var snapshots: [String: InterfaceSnapshot] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let pointer = current {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            var snapshot = snapshots[name, default: InterfaceSnapshot()]

            if let address = interface.ifa_addr {
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    snapshot.ipv4Address = ipv4Address(address)
                case AF_LINK:
                    if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                        snapshot.receivedBytes = UInt64(data.ifi_ibytes)
                        snapshot.sentBytes = UInt64(data.ifi_obytes)
                    }
                default:
                    break
                }
            }

            snapshots[name] = snapshot
            current = interface.ifa_next
        }

        return snapshots
    }

    private static func ipv4Address(_ sockaddrPointer: UnsafePointer<sockaddr>) -> String? {
        guard sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else {
            return nil
        }

        var address = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }

        let addressBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: addressBytes, as: UTF8.self)
    }

    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

private struct NetworkSample: Sendable {
    let counters: NetworkCounters?
    let details: NetworkDetails?
}

private struct NetworkCounters: Sendable {
    let timestampNanoseconds: UInt64
    let interfaceName: String
    let sentBytes: UInt64
    let receivedBytes: UInt64
}

private struct NetworkLiveMetrics: Sendable {
    let sentBytesPerSecond: UInt64
    let receivedBytesPerSecond: UInt64

    static let empty = NetworkLiveMetrics(sentBytesPerSecond: 0, receivedBytesPerSecond: 0)
}

private struct NetworkDetails: Sendable {
    let interfaceName: String
    let adapterName: String
    let connectionType: String
    let dnsName: String
    let ipv4Address: String
    let wifiRSSI: Int?
    let wifiNoise: Int?
    let wifiChannel: Int?
    let wifiBand: String?
    let wifiChannelWidth: String?
    let wifiFrequency: String?

    static let unavailable = NetworkDetails(
        interfaceName: "--",
        adapterName: "Network",
        connectionType: "--",
        dnsName: "--",
        ipv4Address: "--",
        wifiRSSI: nil,
        wifiNoise: nil,
        wifiChannel: nil,
        wifiBand: nil,
        wifiChannelWidth: nil,
        wifiFrequency: nil
    )
}

private struct WiFiDetails {
    let interfaceName: String
    let rssi: Int
    let noise: Int
    let channel: Int?
    let band: String?
    let width: String?
    let frequency: String?
}

private struct InterfaceSnapshot {
    var sentBytes: UInt64 = 0
    var receivedBytes: UInt64 = 0
    var ipv4Address: String?
}
