// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "IndependentConsumer",
    platforms: [.macOS("26.0")],
    dependencies: [.package(url: "https://github.com/raster-labs/SwiftJLI.git", revision: "e7e54f756cccec07a66870ebefd68b5bbb5c79a6")],
    targets: [
        .executableTarget(name: "IndependentConsumer", dependencies: [
            .product(name: "SwiftJLI", package: "swiftjli")
        ])
    ],
    swiftLanguageModes: [.v6]
)
