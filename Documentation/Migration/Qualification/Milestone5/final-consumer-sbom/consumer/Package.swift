// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "IndependentConsumer",
    platforms: [.macOS("26.0")],
    dependencies: [.package(url: "https://github.com/raster-labs/SwiftJLI.git", revision: "f548e5048e5c71204c2a2ec4036bf66c4f040285")],
    targets: [
        .executableTarget(name: "IndependentConsumer", dependencies: [
            .product(name: "SwiftJLI", package: "swiftjli")
        ])
    ],
    swiftLanguageModes: [.v6]
)
