// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "InputAttribution", platforms: [.macOS(.v26)], dependencies: [.package(path: "../JLISwift"), .package(path: "../SwiftJLI")], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "JLISwift", package: "JLISwift"), .product(name: "SwiftJLI", package: "SwiftJLI")])])
