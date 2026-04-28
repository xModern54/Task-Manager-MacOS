import Foundation
import IOKit
import IOKit.ps

actor IOKitSystemBatteryInfoProvider: SystemBatteryInfoProviding {
    private var cachedDetails = SystemBatterySnapshot.unavailable
    private var currentSamples: [BatteryCurrentSample] = []
    private var currentSampleMode: BatteryTimeMode = .idle
    private var lastTimeEstimateUpdate: Date?
    private var cachedTimeToFullMinutes: Int?
    private var cachedTimeToEmptyMinutes: Int?

    private let timeEstimateWindow: TimeInterval = 30
    private let minimumTimeEstimateWindow: TimeInterval = 25
    private let timeEstimateUpdateInterval: TimeInterval = 5

    func snapshot(includeDetails: Bool) async -> SystemBatterySnapshot {
        let powerSourceSnapshot = Self.powerSourceSnapshot()

        guard powerSourceSnapshot.isPresent else {
            cachedDetails = .unavailable
            return .unavailable
        }

        guard includeDetails else {
            return cachedDetails.isPresent
                ? cachedDetails.mergingLightweightValues(from: powerSourceSnapshot)
                : powerSourceSnapshot
        }

        let batteryDetails = Self.appleSmartBatterySnapshot()
        let mergedSnapshot = batteryDetails.isPresent
            ? batteryDetails.mergingLightweightValues(from: powerSourceSnapshot)
            : powerSourceSnapshot
        let snapshot = snapshotWithSmoothedTimeEstimate(mergedSnapshot)

        cachedDetails = snapshot
        return snapshot
    }

    private func snapshotWithSmoothedTimeEstimate(_ snapshot: SystemBatterySnapshot) -> SystemBatterySnapshot {
        let mode = batteryTimeMode(for: snapshot)
        let now = Date()

        guard mode != .idle else {
            resetTimeEstimateSamples(mode: mode)
            return snapshot
        }

        if mode != currentSampleMode {
            resetTimeEstimateSamples(mode: mode)
        }

        if let currentMilliamps = snapshot.currentMilliamps, currentMilliamps != 0 {
            currentSamples.append(BatteryCurrentSample(timestamp: now, currentMilliamps: currentMilliamps))
        }

        currentSamples.removeAll { now.timeIntervalSince($0.timestamp) > timeEstimateWindow }

        let shouldUpdate = lastTimeEstimateUpdate.map { now.timeIntervalSince($0) >= timeEstimateUpdateInterval } ?? true
        if shouldUpdate {
            switch mode {
            case .charging:
                let nextEstimate = robustCurrentMilliamps(for: mode, now: now).flatMap {
                    Self.calculatedTimeToFullMinutes(
                        isCharging: true,
                        isCharged: snapshot.chargeState == "Fully charged",
                        currentChargeMilliampHours: snapshot.currentChargeMilliampHours,
                        maxChargeMilliampHours: snapshot.maxChargeMilliampHours,
                        currentMilliamps: $0
                    )
                }
                cachedTimeToFullMinutes = smoothedEstimate(
                    previous: cachedTimeToFullMinutes,
                    next: nextEstimate ?? snapshot.timeToFullMinutes
                )
                cachedTimeToEmptyMinutes = nil
            case .discharging:
                let nextEstimate = robustCurrentMilliamps(for: mode, now: now).flatMap {
                    Self.calculatedTimeToEmptyMinutes(
                        isDischarging: true,
                        currentChargeMilliampHours: snapshot.currentChargeMilliampHours,
                        currentMilliamps: $0
                    )
                }
                cachedTimeToEmptyMinutes = smoothedEstimate(
                    previous: cachedTimeToEmptyMinutes,
                    next: nextEstimate ?? snapshot.timeToEmptyMinutes
                )
                cachedTimeToFullMinutes = nil
            case .idle:
                break
            }

            lastTimeEstimateUpdate = now
        }

        return snapshot.replacingTimeEstimates(
            timeToFullMinutes: cachedTimeToFullMinutes ?? snapshot.timeToFullMinutes,
            timeToEmptyMinutes: cachedTimeToEmptyMinutes ?? snapshot.timeToEmptyMinutes
        )
    }

    private func batteryTimeMode(for snapshot: SystemBatterySnapshot) -> BatteryTimeMode {
        if snapshot.chargeState == "Charging" {
            return .charging
        }

        if snapshot.powerSource == "Battery" {
            return .discharging
        }

        return .idle
    }

    private func robustCurrentMilliamps(for mode: BatteryTimeMode, now: Date) -> Int? {
        guard let oldestSample = currentSamples.first,
              now.timeIntervalSince(oldestSample.timestamp) >= minimumTimeEstimateWindow else {
            return nil
        }

        let values = currentSamples.compactMap { sample -> Int? in
            switch mode {
            case .charging:
                guard sample.currentMilliamps > 0 else { return nil }
            case .discharging:
                guard sample.currentMilliamps < 0 else { return nil }
            case .idle:
                return nil
            }

            return abs(sample.currentMilliamps)
        }
        .sorted()

        guard values.count >= 6 else { return nil }

        let trimCount = values.count >= 10 ? max(1, Int(Double(values.count) * 0.2)) : 0
        let trimmedValues = Array(values.dropFirst(trimCount).dropLast(trimCount))
        let usableValues = trimmedValues.isEmpty ? values : trimmedValues
        let average = Double(usableValues.reduce(0, +)) / Double(usableValues.count)

        guard average > 0 else { return nil }
        return Int(average.rounded())
    }

    private func smoothedEstimate(previous: Int?, next: Int?) -> Int? {
        guard let next else { return previous }
        guard let previous else { return next }

        let delta = next - previous
        let maximumStep = max(5, Int((Double(previous) * 0.06).rounded()))
        let clampedDelta = min(max(delta, -maximumStep), maximumStep)
        let easedDelta = Int((Double(clampedDelta) * 0.35).rounded())

        return max(previous + (easedDelta == 0 && clampedDelta != 0 ? (clampedDelta > 0 ? 1 : -1) : easedDelta), 0)
    }

    private func resetTimeEstimateSamples(mode: BatteryTimeMode) {
        currentSamples = []
        currentSampleMode = mode
        lastTimeEstimateUpdate = nil
        cachedTimeToFullMinutes = nil
        cachedTimeToEmptyMinutes = nil
    }

    private static func powerSourceSnapshot() -> SystemBatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description[kIOPSTypeKey] as? String
            let isPresent = boolValue(description[kIOPSIsPresentKey]) ?? true
            guard isPresent, type == kIOPSInternalBatteryType else {
                continue
            }

            let currentCapacity = intValue(description[kIOPSCurrentCapacityKey]) ?? 0
            let maxCapacity = max(intValue(description[kIOPSMaxCapacityKey]) ?? 100, 1)
            let level = min(max(Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded()), 0), 100)
            let powerSourceState = description[kIOPSPowerSourceStateKey] as? String ?? "--"
            let isCharging = boolValue(description[kIOPSIsChargingKey]) ?? false
            let isCharged = boolValue(description[kIOPSIsChargedKey]) ?? false
            let timeToFull = intValue(description[kIOPSTimeToFullChargeKey]).flatMap(validTimeRemaining)
            let timeToEmpty = intValue(description[kIOPSTimeToEmptyKey]).flatMap(validTimeRemaining)

            return SystemBatterySnapshot(
                isPresent: true,
                name: description[kIOPSNameKey] as? String ?? "Battery",
                levelPercent: level,
                powerSource: displayPowerSource(powerSourceState),
                chargeState: chargeState(isCharging: isCharging, isCharged: isCharged),
                chargeType: isCharging ? "Charging" : "Not charging",
                technology: "Li-ion",
                cycleCount: nil,
                currentChargeMilliampHours: nil,
                maxChargeMilliampHours: nil,
                designCapacityMilliampHours: nil,
                temperatureCelsius: nil,
                voltageVolts: nil,
                currentMilliamps: nil,
                powerWatts: nil,
                timeToFullMinutes: timeToFull,
                timeToEmptyMinutes: timeToEmpty,
                adapterName: "--",
                adapterWatts: nil
            )
        }

        return .unavailable
    }

    private static func appleSmartBatterySnapshot() -> SystemBatterySnapshot {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else {
            return .unavailable
        }

        defer {
            IOObjectRelease(iterator)
        }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            return .unavailable
        }

        defer {
            IOObjectRelease(entry)
        }

        let installed = boolProperty("BatteryInstalled", from: entry) ?? true
        guard installed else {
            return .unavailable
        }

        let currentChargeMilliampHours = intProperty("AppleRawCurrentCapacity", from: entry)
        let maxChargeMilliampHours = intProperty("AppleRawMaxCapacity", from: entry)
            ?? intProperty("NominalChargeCapacity", from: entry)
        let level = intProperty("CurrentCapacity", from: entry) ?? 0
        let isCharging = boolProperty("IsCharging", from: entry) ?? false
        let fullyCharged = boolProperty("FullyCharged", from: entry) ?? false
        let externalConnected = boolProperty("ExternalConnected", from: entry) ?? false
        let voltageMillivolts = intProperty("Voltage", from: entry) ?? intProperty("AppleRawBatteryVoltage", from: entry)
        let currentMilliamps = signedIntProperty("Amperage", from: entry)
            ?? signedIntProperty("InstantAmperage", from: entry)
        let powerWatts = calculatedPower(voltageMillivolts: voltageMillivolts, currentMilliamps: currentMilliamps)
        let temperatureCelsius = intProperty("Temperature", from: entry).map { Double($0) / 100 }
        let adapterDetails = dictionaryProperty("AdapterDetails", from: entry)
            ?? arrayProperty("AppleRawAdapterDetails", from: entry)?.first
        let chargerData = dictionaryProperty("ChargerData", from: entry)

        return SystemBatterySnapshot(
            isPresent: true,
            name: stringProperty("DeviceName", from: entry) ?? "Battery",
            levelPercent: min(max(level, 0), 100),
            powerSource: externalConnected ? "AC Power" : "Battery",
            chargeState: chargeState(isCharging: isCharging, isCharged: fullyCharged),
            chargeType: chargeType(
                isCharging: isCharging,
                fullyCharged: fullyCharged,
                adapterWatts: intValue(adapterDetails?["Watts"]),
                slowChargingReason: intValue(chargerData?["SlowChargingReason"])
            ),
            technology: "Li-ion",
            cycleCount: intProperty("CycleCount", from: entry),
            currentChargeMilliampHours: currentChargeMilliampHours,
            maxChargeMilliampHours: maxChargeMilliampHours,
            designCapacityMilliampHours: intProperty("DesignCapacity", from: entry),
            temperatureCelsius: temperatureCelsius,
            voltageVolts: voltageMillivolts.map { Double($0) / 1000 },
            currentMilliamps: currentMilliamps,
            powerWatts: powerWatts,
            timeToFullMinutes: intProperty("AvgTimeToFull", from: entry).flatMap(validTimeRemaining),
            timeToEmptyMinutes: intProperty("AvgTimeToEmpty", from: entry).flatMap(validTimeRemaining),
            adapterName: stringValue(adapterDetails?["Name"]) ?? stringValue(adapterDetails?["Description"]) ?? "--",
            adapterWatts: intValue(adapterDetails?["Watts"])
        )
    }

    private static func stringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }

    private static func intProperty(_ key: String, from entry: io_registry_entry_t) -> Int? {
        intValue(
            IORegistryEntryCreateCFProperty(
                entry,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        )
    }

    private static func signedIntProperty(_ key: String, from entry: io_registry_entry_t) -> Int? {
        signedIntValue(
            IORegistryEntryCreateCFProperty(
                entry,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        )
    }

    private static func boolProperty(_ key: String, from entry: io_registry_entry_t) -> Bool? {
        boolValue(
            IORegistryEntryCreateCFProperty(
                entry,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        )
    }

    private static func dictionaryProperty(_ key: String, from entry: io_registry_entry_t) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any]
    }

    private static func arrayProperty(_ key: String, from entry: io_registry_entry_t) -> [[String: Any]]? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [[String: Any]]
    }

    private static func chargeState(isCharging: Bool, isCharged: Bool) -> String {
        if isCharged {
            return "Fully charged"
        }

        return isCharging ? "Charging" : "Not charging"
    }

    private static func chargeType(
        isCharging: Bool,
        fullyCharged: Bool,
        adapterWatts: Int?,
        slowChargingReason: Int?
    ) -> String {
        if fullyCharged {
            return "Full"
        }

        guard isCharging else {
            return "Not charging"
        }

        if let slowChargingReason, slowChargingReason != 0 {
            return "Slow"
        }

        guard let adapterWatts else {
            return "Charging"
        }

        return adapterWatts >= 30 ? "Fast" : "Standard"
    }

    private static func displayPowerSource(_ rawValue: String) -> String {
        switch rawValue {
        case kIOPSACPowerValue:
            return "AC Power"
        case kIOPSBatteryPowerValue:
            return "Battery"
        case kIOPSOffLineValue:
            return "Offline"
        default:
            return rawValue
        }
    }

    private static func calculatedPower(voltageMillivolts: Int?, currentMilliamps: Int?) -> Double? {
        guard let voltageMillivolts, let currentMilliamps else {
            return nil
        }

        return Double(voltageMillivolts * currentMilliamps) / 1_000_000
    }

    private static func calculatedTimeToFullMinutes(
        isCharging: Bool,
        isCharged: Bool,
        currentChargeMilliampHours: Int?,
        maxChargeMilliampHours: Int?,
        currentMilliamps: Int?
    ) -> Int? {
        guard isCharging, !isCharged,
              let currentChargeMilliampHours,
              let maxChargeMilliampHours,
              let currentMilliamps else {
            return nil
        }

        let remainingMilliampHours = max(maxChargeMilliampHours - currentChargeMilliampHours, 0)
        return estimatedMinutes(milliampHours: remainingMilliampHours, currentMilliamps: currentMilliamps)
    }

    private static func calculatedTimeToEmptyMinutes(
        isDischarging: Bool,
        currentChargeMilliampHours: Int?,
        currentMilliamps: Int?
    ) -> Int? {
        guard isDischarging,
              let currentChargeMilliampHours,
              let currentMilliamps else {
            return nil
        }

        return estimatedMinutes(milliampHours: currentChargeMilliampHours, currentMilliamps: currentMilliamps)
    }

    private static func estimatedMinutes(milliampHours: Int, currentMilliamps: Int) -> Int? {
        let absoluteCurrent = abs(currentMilliamps)
        guard milliampHours > 0, absoluteCurrent > 0 else {
            return nil
        }

        let minutes = Int((Double(milliampHours) / Double(absoluteCurrent) * 60).rounded())
        return validTimeRemaining(minutes)
    }

    private static func validTimeRemaining(_ minutes: Int) -> Int? {
        guard minutes >= 0, minutes < 65_535 else {
            return nil
        }

        return minutes
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let value as Int:
            return value
        case let value as UInt64:
            return Int(value)
        case let value as UInt:
            return Int(value)
        default:
            return nil
        }
    }

    private static func signedIntValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as UInt64:
            return Int(bitPattern: UInt(value))
        case let value as UInt:
            return Int(bitPattern: value)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let number as NSNumber:
            return number.boolValue
        default:
            return nil
        }
    }
}

private enum BatteryTimeMode {
    case charging
    case discharging
    case idle
}

private struct BatteryCurrentSample {
    let timestamp: Date
    let currentMilliamps: Int
}

private extension SystemBatterySnapshot {
    func replacingTimeEstimates(timeToFullMinutes: Int?, timeToEmptyMinutes: Int?) -> SystemBatterySnapshot {
        SystemBatterySnapshot(
            isPresent: isPresent,
            name: name,
            levelPercent: levelPercent,
            powerSource: powerSource,
            chargeState: chargeState,
            chargeType: chargeType,
            technology: technology,
            cycleCount: cycleCount,
            currentChargeMilliampHours: currentChargeMilliampHours,
            maxChargeMilliampHours: maxChargeMilliampHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            temperatureCelsius: temperatureCelsius,
            voltageVolts: voltageVolts,
            currentMilliamps: currentMilliamps,
            powerWatts: powerWatts,
            timeToFullMinutes: timeToFullMinutes,
            timeToEmptyMinutes: timeToEmptyMinutes,
            adapterName: adapterName,
            adapterWatts: adapterWatts
        )
    }

    func mergingLightweightValues(from lightweightSnapshot: SystemBatterySnapshot) -> SystemBatterySnapshot {
        SystemBatterySnapshot(
            isPresent: isPresent || lightweightSnapshot.isPresent,
            name: name == "Battery" ? lightweightSnapshot.name : name,
            levelPercent: lightweightSnapshot.levelPercent,
            powerSource: lightweightSnapshot.powerSource == "--" ? powerSource : lightweightSnapshot.powerSource,
            chargeState: lightweightSnapshot.chargeState == "--" ? chargeState : lightweightSnapshot.chargeState,
            chargeType: chargeType,
            technology: technology,
            cycleCount: cycleCount,
            currentChargeMilliampHours: currentChargeMilliampHours,
            maxChargeMilliampHours: maxChargeMilliampHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            temperatureCelsius: temperatureCelsius,
            voltageVolts: voltageVolts,
            currentMilliamps: currentMilliamps,
            powerWatts: powerWatts,
            timeToFullMinutes: lightweightSnapshot.timeToFullMinutes ?? timeToFullMinutes,
            timeToEmptyMinutes: lightweightSnapshot.timeToEmptyMinutes ?? timeToEmptyMinutes,
            adapterName: adapterName,
            adapterWatts: adapterWatts
        )
    }
}
