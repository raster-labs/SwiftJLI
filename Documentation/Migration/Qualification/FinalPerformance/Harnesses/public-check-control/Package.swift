// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MigrationBenchmark", platforms: [.macOS(.v26)],
    dependencies: [.package(name: "JLISwift", path: "../JLISwift"), .package(name: "SwiftJLI", path: "../SwiftJLI-check-final")],
    targets: [.executableTarget(name: "Benchmark", dependencies: [.product(name: "JLISwift", package: "JLISwift"), .product(name: "SwiftJLI", package: "SwiftJLI")])])
