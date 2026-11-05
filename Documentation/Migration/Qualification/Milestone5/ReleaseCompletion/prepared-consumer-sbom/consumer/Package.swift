// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "IndependentConsumer",
    platforms: [.macOS("26.0")],
    dependencies: [.package(url: "https://github.com/raster-labs/SwiftJLI.git", revision: "7739dba554cabebcc25e3593af3feb6ba27f8489")],
    targets: [
        .executableTarget(name: "IndependentConsumer", dependencies: [
            .product(name: "SwiftJLI", package: "swiftjli")
        ])
    ],
    swiftLanguageModes: [.v6]
)
