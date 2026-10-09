// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Corpus", platforms: [.macOS("26.0")], dependencies: [.package(name: "JLISwift", path: "../JLISwift"), .package(name: "SwiftJLI", path: "../SwiftJLI")], targets: [.executableTarget(name: "Corpus", dependencies: [.product(name: "JLISwift", package: "JLISwift"), .product(name: "SwiftJLI", package: "SwiftJLI")])])
