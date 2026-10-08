// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(name: "Memory", platforms: [.macOS("26.0")], dependencies: [.package(name: "JLISwift", path: "../JLISwift"), .package(name: "SwiftJLI", path: "../SwiftJLI")], targets: [.executableTarget(name: "Memory", dependencies: [.product(name: "JLISwift", package: "JLISwift"), .product(name: "SwiftJLI", package: "SwiftJLI")])])
