// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite(.enabled(if: BlockLocalIDCT.available)) struct BlockLocalIDCTTests {
    @Test(arguments: [8, 12], [1, 9, 256, 1024, 1025])
    func floatBitsMatchCanonicalGEMMsAndPreserveGuards(precision: Int, blocks: Int) throws {
        var seed: UInt32 = 0xFA8C1234
        func random() -> UInt32 { seed = seed &* 1664525 &+ 1013904223; return seed }
        try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
            for scale: Float in [1, 17, 65535] {
                for pattern in 0..<4 {
                    var input = [Int32](repeating: 0, count: blocks * 64)
                    for index in input.indices {
                        if pattern == 0 || (pattern == 1 && random() & 7 == 0) ||
                            (pattern == 2 && index % 64 == 0) {
                            input[index] = Int32(random() % 127) - 63
                        }
                    }
                    let quantiser = (0..<64).map { scale == 65535 ? scale : scale + Float($0 % 3) }
                    var expected = [Float](repeating: 0, count: input.count)
                    var scratch = [Float](repeating: 0, count: min(blocks, 1024) * 64)
                    input.withUnsafeBufferPointer { source in
                        quantiser.withUnsafeBufferPointer { qt in
                            expected.withUnsafeMutableBufferPointer { output in
                                scratch.withUnsafeMutableBufferPointer { workspace in
                                    for first in stride(from: 0, to: blocks, by: 1024) {
                                        let count = min(1024, blocks - first)
                                        AccelerateDSP.inverseDCTBatchDequantized(zigzag: source.baseAddress! + first * 64,
                                            quantTable: qt.baseAddress!, output: output.baseAddress! + first * 64,
                                            scratch: workspace.baseAddress!, blockCount: count)
                                    }
                                    var centre = Float(1 << (precision - 1)), low: Float = 0
                                    var high = Float((1 << precision) - 1)
                                    jliDSP_vsadd(output.baseAddress!, 1, &centre, output.baseAddress!, 1, output.count)
                                    jliDSP_vclip(output.baseAddress!, 1, &low, &high, output.baseAddress!, 1, output.count)
                                }
                            }
                        }
                    }
                    var guarded = [Int32](repeating: 919, count: input.count + 7)
                    guarded.replaceSubrange(3..<(3 + input.count), with: input)
                    try guarded.withUnsafeMutableBufferPointer { storage in
                        let coefficients = UnsafeMutableBufferPointer(rebasing: storage[3..<(3 + input.count)])
                        try quantiser.withUnsafeBufferPointer { qt in
                            // Retain the canonical 1024-block GEMM oracle above,
                            // but reconstruct through the new 256-block windows.
                            for firstBlock in stride(from: 0, to: blocks, by: 256) {
                                let first = firstBlock * 64, count = min(256, blocks - firstBlock) * 64
                                try BlockLocalIDCT.reconstruct(.init(rebasing: coefficients[first..<(first + count)]),
                                    quantiser: qt, precision: precision)
                            }
                        }
                        coefficients.baseAddress!.withMemoryRebound(to: Float.self, capacity: coefficients.count) { result in
                            let firstDifference = expected.indices.first { expected[$0].bitPattern != result[$0].bitPattern }
                            #expect(firstDifference == nil, "Float mismatch at \(String(describing: firstDifference)); pattern \(pattern), scale \(scale)")
                        }
                    }
                    #expect(guarded.prefix(3).allSatisfy { $0 == 919 })
                    #expect(guarded.suffix(4).allSatisfy { $0 == 919 })
                }
            }
        }
    }

    @Test func malformedWindowsRejectBeforeChangingStorage() {
        NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
            for (count, precision, quantisers) in [(0, 8, 64), (63, 8, 64), (64, 7, 64), (64, 12, 63)] {
                var values = [Int32](repeating: 919, count: count)
                let table = [Float](repeating: 1, count: quantisers)
                #expect(throws: JLIError.self) {
                    try values.withUnsafeMutableBufferPointer { coefficients in
                        try table.withUnsafeBufferPointer { quantiser in
                            try BlockLocalIDCT.reconstruct(coefficients, quantiser: quantiser, precision: precision)
                        }
                    }
                }
                #expect(values.allSatisfy { $0 == 919 })
            }
        }
    }
}
