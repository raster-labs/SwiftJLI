// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct ConstantDCTWriterTests {
    @Test(arguments: [8, 12])
    func constantTilesMatchExpandedSamplesIncludingPaddingAndFloatBits(precision: Int) throws {
        let maximum = Float((1 << precision) - 1)
        let samples: [Float] = [-0.0, 0.5, 1.5, 2.5, 0.499, maximum - 0.5, maximum, maximum + 1]
        for (width, height) in [(1, 1), (2, 9), (3, 17), (7, 9), (8, 17), (9, 9),
                                (15, 17), (16, 9), (19, 17), (513, 257)] {
            let blocksPerRow = (width + 7) / 8
            let blockCount = blocksPerRow * ((height + 7) / 8)
            let values = (0..<blockCount).map { samples[$0 % samples.count] }
            let expanded = values.flatMap { [Float](repeating: $0, count: 64) }
            for floating in [false, true] {
                let bps = floating ? 4 : precision == 8 ? 1 : 2
                let rowBytes = width * bps + 5
                var expected = [UInt8](repeating: 0xA5, count: 3 + rowBytes * height + 7)
                var actual = expected
                try expected.withUnsafeMutableBytes { raw in
                    let output = UnsafeMutableRawBufferPointer(rebasing: raw[3..<(raw.count - 7)])
                    try expanded.withUnsafeBufferPointer {
                        try SharedDCTStorage.writeGreyscaleBlocks($0, firstBlock: 0,
                            blocksPerRow: blocksPerRow, width: width, height: height,
                            precision: precision, floatOutput: floating,
                            into: .init(bytes: output, rowBytes: rowBytes, bytesPerSample: bps))
                    }
                }
                try actual.withUnsafeMutableBytes { raw in
                    let output = UnsafeMutableRawBufferPointer(rebasing: raw[3..<(raw.count - 7)])
                    try values.withUnsafeBufferPointer { source in
                        // Small splits cross block rows; the large case also
                        // reaches two full1024 batches and an odd final tail.
                        let chunk = blockCount > 1024 ? 1024 : 5
                        for first in stride(from: 0, to: blockCount, by: chunk) {
                            let end = min(first + chunk, blockCount)
                            try SharedDCTStorage.writeGreyscaleConstantBlocks(
                                UnsafeBufferPointer(rebasing: source[first..<end]), firstBlock: first,
                                blocksPerRow: blocksPerRow, width: width, height: height,
                                precision: precision, floatOutput: floating,
                                into: .init(bytes: output, rowBytes: rowBytes, bytesPerSample: bps))
                        }
                    }
                }
                #expect(actual == expected)
                #expect(actual.prefix(3).allSatisfy { $0 == 0xA5 })
                #expect(actual.suffix(7).allSatisfy { $0 == 0xA5 })
                if floating { #expect(Array(actual[3..<7]) == [0, 0, 0, 128]) }
            }
        }
    }

    @Test func nonFiniteConstantIsRejectedBeforeDestinationWrites() throws {
        for invalid: Float in [.nan, .infinity, -.infinity] {
            for bps in [1, 2, 4] {
                var bytes = [UInt8](repeating: 0xA5, count: 64 * bps)
                #expect(throws: JLIError.self) {
                    try bytes.withUnsafeMutableBytes { raw in
                        try [invalid].withUnsafeBufferPointer {
                            try SharedDCTStorage.writeGreyscaleConstantBlocks($0, firstBlock: 0,
                                blocksPerRow: 1, width: 8, height: 8, precision: bps == 1 ? 8 : 12,
                                floatOutput: bps == 4,
                                into: .init(bytes: raw, rowBytes: 8 * bps, bytesPerSample: bps))
                        }
                    }
                }
                #expect(bytes.allSatisfy { $0 == 0xA5 })
            }
        }
    }

    @Test func levelShiftAndClipKeepBitsWhenEachDCIsProcessedOnce() {
        let basis = AccelerateDSP.dctMatrix[0]
        for backend in Decoder.capabilities.availableBackends {
            NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                for precision in [8, 12] {
                    for first in stride(from: -16384, through: 16384, by: 1024) {
                        let count = min(1024, 16385 - first)
                        var values = (0..<count).map { (Float(first + $0) * basis) * basis }
                        var expanded = values.flatMap { [Float](repeating: $0, count: 64) }
                        var center = Float(1 << (precision - 1)), low: Float = 0
                        var high = Float((1 << precision) - 1)
                        values.withUnsafeMutableBufferPointer { v in
                            jliDSP_vsadd(v.baseAddress!, 1, &center, v.baseAddress!, 1, v.count)
                            jliDSP_vclip(v.baseAddress!, 1, &low, &high, v.baseAddress!, 1, v.count)
                        }
                        expanded.withUnsafeMutableBufferPointer { e in
                            jliDSP_vsadd(e.baseAddress!, 1, &center, e.baseAddress!, 1, e.count)
                            jliDSP_vclip(e.baseAddress!, 1, &low, &high, e.baseAddress!, 1, e.count)
                        }
                        #expect(expanded.indices.allSatisfy { expanded[$0].bitPattern == values[$0 / 64].bitPattern })
                    }
                }
            }
        }
    }
}
