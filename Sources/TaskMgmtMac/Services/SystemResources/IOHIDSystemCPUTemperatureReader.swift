import Foundation
import IOKit

private typealias IOHIDEventSystemClientRef = CFTypeRef
private typealias IOHIDServiceClientRef = CFTypeRef
private typealias IOHIDEventRef = CFTypeRef

private let hidTemperatureEventType: Int64 = 15
private let hidTemperatureEventField: Int32 = Int32(hidTemperatureEventType << 16)

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<IOHIDEventSystemClientRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClientRef,
    _ type: Int64,
    _ options: Int32,
    _ timestamp: Int64
) -> Unmanaged<IOHIDEventRef>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

enum IOHIDSystemCPUTemperatureReader {
    static func temperatureCelsius() -> Double? {
        sensorReadings().cpuTemperature
    }

    static func sensorReadings() -> (cpuTemperature: Double?, all: [(name: String, temperature: Double)]) {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            return (nil, [])
        }

        let matching = [
            "PrimaryUsagePage": NSNumber(value: 0xff00),
            "PrimaryUsage": NSNumber(value: 5)
        ] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)

        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() else {
            return (nil, [])
        }

        var allReadings: [(name: String, temperature: Double)] = []
        var appleSiliconCoreReadings: [Double] = []
        var dieReadings: [Double] = []

        for index in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, index), to: IOHIDServiceClientRef.self)
            guard let name = stringProperty("Product", from: service),
                  let event = IOHIDServiceClientCopyEvent(
                    service,
                    hidTemperatureEventType,
                    0,
                    0
                  )?.takeRetainedValue() else {
                continue
            }

            let temperature = IOHIDEventGetFloatValue(event, hidTemperatureEventField)
            guard isPlausibleTemperature(temperature) else {
                continue
            }

            allReadings.append((name: name, temperature: temperature))

            if name.hasPrefix("pACC") || name.hasPrefix("eACC") {
                appleSiliconCoreReadings.append(temperature)
            } else if isDieTemperatureSensor(name) {
                dieReadings.append(temperature)
            }
        }

        let cpuTemperature = hottestTemperature(in: appleSiliconCoreReadings)
            ?? hottestTemperature(in: dieReadings)

        return (cpuTemperature, allReadings)
    }

    private static func stringProperty(_ key: String, from service: IOHIDServiceClientRef) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString)?
            .takeRetainedValue() as? String
    }

    private static func isDieTemperatureSensor(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix("pmu")
            && lowercasedName.contains("tdie")
            && !lowercasedName.contains("tcal")
    }

    private static func isPlausibleTemperature(_ temperature: Double) -> Bool {
        temperature > 0 && temperature < 130
    }

    private static func hottestTemperature(in temperatures: [Double]) -> Double? {
        temperatures.max()
    }
}
