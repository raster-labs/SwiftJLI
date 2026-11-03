// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct BoundedDCTWorkspaceTests {
    @Test(arguments: [8, 12])
    func reusedWorkerScratchPreservesOddEdgesAndCallerPadding(precision: Int) throws {
        // 65 x 98 blocks span several 1024-block batches and do not divide
        // evenly among three workers. The final block has partial rows/columns.
        let width = 513, height = 777, bps = precision == 8 ? 1 : 2
        var source = [UInt8](repeating: 0, count: width * height * bps)
        for y in 0..<height { for x in 0..<width {
            let value = (x * 17 + y * 31 + x * y % 257) & ((1 << precision) - 1)
            source[(y * width + x) * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { source[(y * width + x) * bps + 1] = UInt8(value >> 8) }
        } }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: precision == 8 ? .uint8 : .uint16, colorModel: .grayscale, data: source)
        for progressive in [false, true] {
            let jpeg = try JLIEncoder().encode(image,
                configuration: .init(quality: 87, progressive: progressive))
            var parser = MarkerReader(data: jpeg)
            let parsed = try parser.parse()
            let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
                try JLIDecoder().decodeParsed(parsed).data
            }
            for workers in [1, 3] {
                let rowBytes = width * bps + 7
                var destination = [UInt8](repeating: 0xA5, count: 3 + rowBytes * height + 5)
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: workers)) {
                    try destination.withUnsafeMutableBytes { raw in
                        _ = try JLIDecoder().decodeParsed(parsed, borrowedDestination: .init(
                            bytes: .init(rebasing: raw[3..<(3 + rowBytes * height)]),
                            rowBytes: rowBytes, bytesPerSample: bps))
                    }
                }
                for y in 0..<height {
                    #expect(destination[(3 + y * rowBytes)..<(3 + y * rowBytes + width * bps)]
                        .elementsEqual(expected[(y * width * bps)..<((y + 1) * width * bps)]))
                    #expect(destination[(3 + y * rowBytes + width * bps)..<(3 + (y + 1) * rowBytes)]
                        .allSatisfy { $0 == 0xA5 })
                }
                #expect(destination.prefix(3).allSatisfy { $0 == 0xA5 })
                #expect(destination.suffix(5).allSatisfy { $0 == 0xA5 })
            }
        }
    }
}
