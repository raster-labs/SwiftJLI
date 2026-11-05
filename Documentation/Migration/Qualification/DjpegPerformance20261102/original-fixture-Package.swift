// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemoryCurrent",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "JLISwift", path: "/private/tmp/jliswift-benchmark-20261102"),
        .package(name: "SwiftJLI", path: "/private/tmp/swiftjli-benchmark-20261102")
    ],
    targets: [
        .executableTarget(name: "Memory", dependencies: [
            .product(name: "JLISwift", package: "JLISwift"),
            .product(name: "SwiftJLI", package: "SwiftJLI")
        ])
    ]
)
