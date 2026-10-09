// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(name: "PredecessorComparison",
    platforms: [.macOS("26.0"), .iOS("26.0"), .tvOS("26.0"), .watchOS("26.0"), .visionOS("26.0")],
    dependencies: [
        .package(name: "SwiftJLI", path: "../.."),
        .package(url: "https://github.com/raster-labs/JLISwift.git",
                 revision: "0a4ded0b0b2e8e38127f4f302b286e74ee352474")
    ],
    targets: [
        .target(name: "LegacyIdentity", dependencies: [.product(name: "JLISwift", package: "JLISwift")]),
        .target(name: "SuccessorIdentity", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")]),
        .executableTarget(name: "CompareIdentity", dependencies: ["LegacyIdentity", "SuccessorIdentity"]),
        .testTarget(name: "PredecessorComparisonTests", dependencies: ["LegacyIdentity", "SuccessorIdentity"])
    ], swiftLanguageModes: [.v6])
