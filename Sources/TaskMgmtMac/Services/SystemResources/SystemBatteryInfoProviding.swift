import Foundation

protocol SystemBatteryInfoProviding: Sendable {
    func snapshot(includeDetails: Bool) async -> SystemBatterySnapshot
}

struct SystemBatterySnapshot: Sendable {
    let isPresent: Bool
    let name: String
    let levelPercent: Int
    let powerSource: String
    let chargeState: String
    let chargeType: String
    let technology: String
    let cycleCount: Int?
    let currentChargeMilliampHours: Int?
    let maxChargeMilliampHours: Int?
    let designCapacityMilliampHours: Int?
    let temperatureCelsius: Double?
    let voltageVolts: Double?
    let currentMilliamps: Int?
    let powerWatts: Double?
    let timeToFullMinutes: Int?
    let adapterName: String
    let adapterWatts: Int?

    static let unavailable = SystemBatterySnapshot(
        isPresent: false,
        name: "Battery",
        levelPercent: 0,
        powerSource: "--",
        chargeState: "--",
        chargeType: "--",
        technology: "Li-ion",
        cycleCount: nil,
        currentChargeMilliampHours: nil,
        maxChargeMilliampHours: nil,
        designCapacityMilliampHours: nil,
        temperatureCelsius: nil,
        voltageVolts: nil,
        currentMilliamps: nil,
        powerWatts: nil,
        timeToFullMinutes: nil,
        adapterName: "--",
        adapterWatts: nil
    )
}
