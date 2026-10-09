// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(name: "AllocationProbe",
    products: [.library(name: "HeapProbe", targets: ["HeapProbe"])],
    dependencies: [.package(name: "SwiftJLI", path: "../..")],
    targets: [
        .target(name: "HeapProbe", cSettings: [.unsafeFlags(["-fno-builtin"])],
                linkerSettings: [.linkedLibrary("pthread")]),
        .executableTarget(name: "AllocationProbe", dependencies: ["HeapProbe",
            .product(name: "SwiftJLI", package: "SwiftJLI")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "--export-dynamic"])])
    ])
