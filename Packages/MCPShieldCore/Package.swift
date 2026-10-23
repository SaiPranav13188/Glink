// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPShieldCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MCPShieldCore", targets: ["MCPShieldCore"]),
    ],
    targets: [
        .target(name: "MCPShieldCore"),
        .testTarget(name: "MCPShieldCoreTests", dependencies: ["MCPShieldCore"]),
    ]
)
