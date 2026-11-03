// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "IndependentConsumer",
    platforms: [.macOS("26.0")],
    dependencies: [.package(url: "https://github.com/raster-labs/SwiftJLI.git", revision: "8ae2762710d6279cd92222f5bb5ca95f042f694e")],
    targets: [
        .executableTarget(name: "IndependentConsumer", dependencies: [
            .product(name: "SwiftJLI", package: "swiftjli")
        ])
    ],
    swiftLanguageModes: [.v6]
)
