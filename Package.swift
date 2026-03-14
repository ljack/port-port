// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "port-port",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PortPortCore", targets: ["PortPortCore"]),
        .executable(name: "port-port-mcp", targets: ["PortPortMCP"]),
        .executable(name: "port-port", targets: ["PortPortApp"]),
    ],
    targets: [
        .target(
            name: "PortPortCore",
            path: "Sources/PortPortCore"
        ),
        .executableTarget(
            name: "PortPortApp",
            dependencies: ["PortPortCore"],
            path: "Sources/PortPortApp",
            exclude: ["Info.plist", "PortPortApp.entitlements"]
        ),
        .executableTarget(
            name: "PortPortMCP",
            dependencies: ["PortPortCore"],
            path: "Sources/PortPortMCP"
        ),
        .testTarget(
            name: "PortPortCoreTests",
            dependencies: ["PortPortCore"],
            path: "Tests/PortPortCoreTests"
        ),
    ]
)
