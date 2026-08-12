// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaskMgmtMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskMgmtMac", targets: ["TaskMgmtMac"]),
        .executable(name: "TaskMgmtMacPrivilegedHelper", targets: ["TaskMgmtMacPrivilegedHelper"])
    ],
    targets: [
        .target(
            name: "PrivilegedHelperIPC",
            path: "Sources/PrivilegedHelperIPC"
        ),
        .executableTarget(
            name: "TaskMgmtMac",
            dependencies: ["PrivilegedHelperIPC"],
            path: "Sources/TaskMgmtMac"
        ),
        .executableTarget(
            name: "TaskMgmtMacPrivilegedHelper",
            dependencies: ["PrivilegedHelperIPC"],
            path: "Sources/TaskMgmtMacPrivilegedHelper"
        ),
        .testTarget(
            name: "TaskMgmtMacTests",
            dependencies: ["TaskMgmtMac"],
            path: "Tests/TaskMgmtMacTests"
        )
    ]
)
