// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

// Development-only integration. The shipping SwiftJLI package has no suite dependency.
let package = Package(
    name: "CrossCodecIntegration",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(name: "SwiftJLI", path: "../.."),
        .package(path: "../AllocationProbe"),
        .package(url: "https://github.com/raster-labs/SwiftJ2K.git",
                 revision: "be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748")
    ],
    targets: [.executableTarget(name: "CrossCodecIntegration", dependencies: [
        .product(name: "SwiftJLI", package: "SwiftJLI"),
        .product(name: "SwiftJ2K", package: "SwiftJ2K"),
        .product(name: "HeapProbe", package: "AllocationProbe", condition: .when(platforms: [.linux]))
    ], linkerSettings: [.unsafeFlags(["-Xlinker", "--export-dynamic"], .when(platforms: [.linux]))])],
    swiftLanguageModes: [.v6]
)
