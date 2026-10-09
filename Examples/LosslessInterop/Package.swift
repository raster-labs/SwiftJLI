// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OracleConsumer", platforms: [.macOS("26.0")],
    dependencies: [.package(name: "SwiftJLI", path: "../..")],
    targets: [.executableTarget(name: "Oracle", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")])])
