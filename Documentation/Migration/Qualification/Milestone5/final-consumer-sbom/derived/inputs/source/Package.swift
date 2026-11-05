// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "SwiftJLI",
    platforms: [
        .macOS("26.0"), .iOS("26.0"), .tvOS("26.0"),
        .watchOS("26.0"), .visionOS("26.0")
    ],
    products: [.library(name: "SwiftJLI", targets: ["SwiftJLI"]),
               .executable(name: "swiftjli-cli", targets: ["SwiftJLICLI"])],
    targets: [
        .target(name: "SwiftJLI"),
        .executableTarget(name: "SwiftJLICLI", dependencies: ["SwiftJLI"]),
        .testTarget(name: "SwiftJLITests", dependencies: ["SwiftJLI"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
