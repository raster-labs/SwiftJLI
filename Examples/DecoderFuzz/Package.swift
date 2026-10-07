// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(name: "DecoderFuzz", platforms: [.macOS("26.0")],
    dependencies: [.package(name: "SwiftJLI", path: "../..")],
    targets: [.executableTarget(name: "DecoderFuzz", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")])])
