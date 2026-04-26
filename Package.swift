// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaskMgmtMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskMgmtMac", targets: ["TaskMgmtMac"]),
        .executable(name: "TaskMgmtMacPrivilegedSensorHelper", targets: ["TaskMgmtMacPrivilegedSensorHelper"])
    ],
    targets: [
        .executableTarget(
            name: "TaskMgmtMac",
            path: "Sources/TaskMgmtMac"
        ),
        .executableTarget(
            name: "TaskMgmtMacPrivilegedSensorHelper",
            path: "Sources/TaskMgmtMacPrivilegedSensorHelper",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/PrivilegedSensorHelperInfo.plist"
                ])
            ]
        )
    ]
)
