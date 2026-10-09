// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "ProfileAudit", platforms: [.macOS(.v26)],
    dependencies: [.package(name: "JLISwift", path: "../JLISwift"), .package(name: "SwiftJLI", path: "../SwiftJLI")],
    targets: [.executableTarget(name: "ProfileAudit", dependencies: [.product(name: "JLISwift", package: "JLISwift"), .product(name: "SwiftJLI", package: "SwiftJLI")])])
