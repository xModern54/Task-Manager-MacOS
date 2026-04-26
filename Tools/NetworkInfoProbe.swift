import Darwin
import Foundation
import SystemConfiguration

struct InterfaceCounters {
    var receivedBytes: UInt64 = 0
    var sentBytes: UInt64 = 0
    var ipv4Address: String?
}

struct PrimaryNetworkInfo {
    let interfaceName: String
    let serviceID: String?
    let adapterName: String
    let connectionType: String
    let dnsName: String
    let dnsServers: [String]
    let ipv4Address: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(bytes))
}

func formatRate(_ bytes: UInt64, elapsedSeconds: Double) -> String {
    guard elapsedSeconds > 0 else { return "0 KB/s" }
    return "\(formatBytes(UInt64(Double(bytes) / elapsedSeconds)))/s"
}

func stringAddress(_ sockaddrPointer: UnsafePointer<sockaddr>) -> String? {
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

    return String(cString: buffer)
}

func interfaceCounters() -> [String: InterfaceCounters] {
    var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrsPointer) == 0, let first = ifaddrsPointer else {
        return [:]
    }

    defer {
        freeifaddrs(first)
    }

    var counters: [String: InterfaceCounters] = [:]
    var current: UnsafeMutablePointer<ifaddrs>? = first

    while let pointer = current {
        let interface = pointer.pointee
        let name = String(cString: interface.ifa_name)
        var entry = counters[name, default: InterfaceCounters()]

        if let address = interface.ifa_addr {
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                entry.ipv4Address = stringAddress(address)
            case AF_LINK:
                if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    entry.receivedBytes = UInt64(data.ifi_ibytes)
                    entry.sentBytes = UInt64(data.ifi_obytes)
                }
            default:
                break
            }
        }

        counters[name] = entry
        current = interface.ifa_next
    }

    return counters
}

func primaryInterfaceInfo(store: SCDynamicStore) -> (interfaceName: String, serviceID: String?)? {
    guard let globalIPv4 = SCDynamicStoreCopyValue(
        store,
        "State:/Network/Global/IPv4" as CFString
    ) as? [String: Any],
          let interfaceName = globalIPv4["PrimaryInterface"] as? String else {
        return nil
    }

    return (interfaceName, globalIPv4["PrimaryService"] as? String)
}

func dnsInfo(store: SCDynamicStore, serviceID: String?) -> (name: String, servers: [String]) {
    let keys = [
        serviceID.map { "State:/Network/Service/\($0)/DNS" },
        "State:/Network/Global/DNS"
    ].compactMap { $0 }

    for key in keys {
        guard let dns = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
            continue
        }

        let searchDomains = dns["SearchDomains"] as? [String] ?? []
        let domainName = dns["DomainName"] as? String
        let serverAddresses = dns["ServerAddresses"] as? [String] ?? []

        if domainName != nil || !searchDomains.isEmpty || !serverAddresses.isEmpty {
            return (domainName ?? searchDomains.first ?? "--", serverAddresses)
        }
    }

    return ("--", [])
}

func configuredServiceName(store: SCDynamicStore, serviceID: String?) -> String? {
    guard let serviceID,
          let service = SCDynamicStoreCopyValue(
            store,
            "Setup:/Network/Service/\(serviceID)" as CFString
          ) as? [String: Any] else {
        return nil
    }

    return service["UserDefinedName"] as? String
}

func connectionType(for interfaceName: String, fallbackName: String?) -> String {
    if let fallbackName, !fallbackName.isEmpty {
        return fallbackName
    }

    if interfaceName.hasPrefix("en") {
        return "Ethernet/Wi-Fi"
    }

    if interfaceName.hasPrefix("utun") {
        return "Tunnel"
    }

    return interfaceName
}

func primaryNetworkInfo() -> PrimaryNetworkInfo? {
    guard let store = SCDynamicStoreCreate(nil, "NetworkInfoProbe" as CFString, nil, nil),
          let primary = primaryInterfaceInfo(store: store) else {
        return nil
    }

    let counters = interfaceCounters()
    let primaryCounters = counters[primary.interfaceName] ?? InterfaceCounters()
    let dns = dnsInfo(store: store, serviceID: primary.serviceID)
    let serviceName = configuredServiceName(store: store, serviceID: primary.serviceID)

    return PrimaryNetworkInfo(
        interfaceName: primary.interfaceName,
        serviceID: primary.serviceID,
        adapterName: serviceName ?? primary.interfaceName,
        connectionType: connectionType(for: primary.interfaceName, fallbackName: serviceName),
        dnsName: dns.name,
        dnsServers: dns.servers,
        ipv4Address: primaryCounters.ipv4Address ?? "--",
        receivedBytes: primaryCounters.receivedBytes,
        sentBytes: primaryCounters.sentBytes
    )
}

guard let first = primaryNetworkInfo() else {
    print("No primary network interface found")
    exit(1)
}

print("Primary network")
print("  interface: \(first.interfaceName)")
print("  service ID: \(first.serviceID ?? "--")")
print("  adapter name: \(first.adapterName)")
print("  connection type: \(first.connectionType)")
print("  DNS name: \(first.dnsName)")
print("  DNS servers: \(first.dnsServers.isEmpty ? "--" : first.dnsServers.joined(separator: ", "))")
print("  IPv4 address: \(first.ipv4Address)")
print("  lifetime sent: \(formatBytes(first.sentBytes))")
print("  lifetime received: \(formatBytes(first.receivedBytes))")

let interval = 1.0
Thread.sleep(forTimeInterval: interval)

guard let second = primaryNetworkInfo() else {
    exit(0)
}

let sentDelta = second.sentBytes >= first.sentBytes ? second.sentBytes - first.sentBytes : 0
let receivedDelta = second.receivedBytes >= first.receivedBytes ? second.receivedBytes - first.receivedBytes : 0

print("")
print("One-second live sample")
print("  send: \(formatRate(sentDelta, elapsedSeconds: interval))")
print("  receive: \(formatRate(receivedDelta, elapsedSeconds: interval))")
