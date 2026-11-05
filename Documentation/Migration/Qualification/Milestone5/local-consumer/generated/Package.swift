// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "FreshConsumer", platforms: [.macOS("26.0")],
 dependencies: [.package(name: "SwiftJLI", path: "/Users/pushparaj/projects/SwiftJLI-milestone5")],
 targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")])],
 swiftLanguageModes: [.v6])
