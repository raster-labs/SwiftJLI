// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RGBOutputProbe", platforms: [.macOS(.v26)], dependencies: [.package(path: "../SwiftJLI")], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "SwiftJLI", package: "SwiftJLI")])])
