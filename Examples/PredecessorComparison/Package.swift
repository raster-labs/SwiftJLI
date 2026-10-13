// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
import Foundation

// Run both modes: preserve the migration baseline and independently check the
// seven corrected decoded records against the maintenance fix on this runtime.
let centred = ProcessInfo.processInfo.environment["JLISWIFT_CENTERED_REFERENCE"] == "1"
let reference = centred ? "981da4efb7d62e4370c5d6de706d56a729b9552e"
                        : "0a4ded0b0b2e8e38127f4f302b286e74ee352474"
let package = Package(name: "PredecessorComparison",
    platforms: [.macOS("26.0"), .iOS("26.0"), .tvOS("26.0"), .watchOS("26.0"), .visionOS("26.0")],
    dependencies: [
        .package(name: "SwiftJLI", path: "../.."),
        .package(url: "https://github.com/raster-labs/JLISwift.git",
                 revision: reference)
    ],
    targets: [
        .target(name: "IdentityExpectations", swiftSettings: centred ? [.define("CENTERED_REFERENCE")] : []),
        .target(name: "LegacyIdentity", dependencies: [.product(name: "JLISwift", package: "JLISwift")]),
        .target(name: "SuccessorIdentity", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")]),
        .executableTarget(name: "CompareIdentity", dependencies: ["LegacyIdentity", "SuccessorIdentity", "IdentityExpectations"]),
        .testTarget(name: "PredecessorComparisonTests", dependencies: ["LegacyIdentity", "SuccessorIdentity", "IdentityExpectations"])
    ], swiftLanguageModes: [.v6])
