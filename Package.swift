// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaskMgmtMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskMgmtMac", targets: ["TaskMgmtMac"])
    ],
    targets: [
        .executableTarget(
            name: "TaskMgmtMac",
            path: "Sources/TaskMgmtMac"
        )
    ]
)
