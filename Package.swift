// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glink",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Glink", targets: ["Glink"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // Tollgate's MCP rules engine, vendored (rules, scoring, redaction, eval set).
        .package(path: "Packages/MCPShieldCore"),
    ],
    targets: [
        // Pure logic (no AppKit): fuzzy matching, calculator, snippets, MCP rules.
        .target(
            name: "GlinkCore",
            dependencies: [.product(name: "MCPShieldCore", package: "MCPShieldCore")],
            path: "GlinkCore"
        ),
        .executableTarget(
            name: "Glink",
            dependencies: [
                "GlinkCore",
                .product(name: "MCPShieldCore", package: "MCPShieldCore"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Glink",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                // Sparkle.framework is embedded in Glink.app/Contents/Frameworks by scripts/build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "GlinkCoreTests",
            dependencies: ["GlinkCore"],
            path: "Tests/GlinkCoreTests"
        ),
    ]
)
