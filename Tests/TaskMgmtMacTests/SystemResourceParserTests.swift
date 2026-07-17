import Testing
@testable import TaskMgmtMac

@Test func parsesLegacyPerformanceAndEfficiencyClusterFrequencies() {
    let output = """
    E-Cluster HW active frequency: 1512 MHz
    P-Cluster HW active frequency: 3.24 GHz
    """

    let snapshot = PowermetricsCPUSensorParser.snapshot(from: output)

    #expect(snapshot.efficiencyFrequencyMHz == 1512)
    #expect(snapshot.performanceFrequencyMHz == 3240)
}

@Test func parsesM5SuperAndNumberedClusterFrequencies() {
    let output = """
    E0-Cluster HW active frequency: 1100 MHz
    S-Cluster HW active frequency: 0 MHz
    S0-Cluster HW active frequency: 4.12 GHz
    """

    let snapshot = PowermetricsCPUSensorParser.snapshot(from: output)

    #expect(snapshot.efficiencyFrequencyMHz == 1100)
    #expect(snapshot.performanceFrequencyMHz == 2060)
}

@Test func diskSelectionPrefersPrimaryWholeDiskOverEarlierGenericDriver() {
    let generic = DiskStatsSelectionRank(
        isPrimaryDisk: false,
        isInternalWholeDisk: false,
        hasWholeMedia: false,
        operationCount: 0,
        byteCount: 0
    )
    let primary = DiskStatsSelectionRank(
        isPrimaryDisk: true,
        isInternalWholeDisk: true,
        hasWholeMedia: true,
        operationCount: 100,
        byteCount: 1_000
    )

    #expect(generic < primary)
}

@Test func diskSelectionKeepsPrimaryDiskAheadOfBusyExternalStorage() {
    let primary = DiskStatsSelectionRank(
        isPrimaryDisk: true,
        isInternalWholeDisk: true,
        hasWholeMedia: true,
        operationCount: 1,
        byteCount: 1
    )
    let external = DiskStatsSelectionRank(
        isPrimaryDisk: false,
        isInternalWholeDisk: false,
        hasWholeMedia: true,
        operationCount: .max,
        byteCount: .max
    )

    #expect(external < primary)
}
