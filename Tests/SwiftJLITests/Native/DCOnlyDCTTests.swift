// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct DCOnlyDCTTests {
    // The retained generic two-matrix implementation is independent of the
    // DC shortcut, and keeps exactly the same batch dimensions as production.
    private func compare(_ coefficients: [Int32], quantiser: Float,
                         clipPrecision: Int? = nil) {
        let blocks = coefficients.count / 64
        let table = [Float](repeating: quantiser, count: 64)
        var natural = [Float](repeating: 0, count: coefficients.count)
        for block in 0..<blocks { for index in 0..<64 {
            natural[block * 64 + index] = Float(coefficients[block * 64
                + Quantization.inverseZigzagOrder[index]]) * table[index]
        } }
        var expected = [Float](repeating: 0, count: coefficients.count)
        var referenceScratch = expected
        AccelerateDSP.inverseDCTBatch(natural, into: &expected,
            scratch: &referenceScratch, blockCount: blocks)

        let sentinel: Float = 123456
        var actual = [Float](repeating: sentinel, count: coefficients.count + 8)
        var scratch = [Float](repeating: sentinel, count: coefficients.count + 8)
        coefficients.withUnsafeBufferPointer { c in
            table.withUnsafeBufferPointer { q in
                actual.withUnsafeMutableBufferPointer { a in
                    scratch.withUnsafeMutableBufferPointer { s in
                        AccelerateDSP.inverseDCTBatchDequantized(zigzag: c.baseAddress!,
                            quantTable: q.baseAddress!, output: a.baseAddress! + 3,
                            scratch: s.baseAddress! + 3, blockCount: blocks)
                    }
                }
            }
        }
        #expect(actual.prefix(3).allSatisfy { $0 == sentinel })
        #expect(actual.suffix(5).allSatisfy { $0 == sentinel })
        #expect(scratch.prefix(3).allSatisfy { $0 == sentinel })
        #expect(scratch.suffix(5).allSatisfy { $0 == sentinel })
        let mismatch = expected.indices.first { expected[$0].bitPattern != actual[$0 + 3].bitPattern }
        #expect(mismatch == nil, "Raw Float bits differ: blocks=\(blocks), q=\(quantiser), index=\(String(describing: mismatch))")

        // The streaming path consumes DC values into independent scratch before
        // it rebinds coefficient storage. Check its Float bits against the same
        // independent generic transform, including mixed-AC fallback and tails.
        var reused = coefficients
        reused.withUnsafeMutableBufferPointer { c in
            table.withUnsafeBufferPointer { q in
                scratch.withUnsafeMutableBufferPointer { s in
                    let count = c.count, workspace = s.baseAddress! + 3
                    let dcOnly = AccelerateDSP.prepareDCOnlyDCTBatch(zigzag: UnsafePointer(c.baseAddress!),
                        quantTable: q.baseAddress!, scratch: workspace, blockCount: blocks)
                    if !dcOnly {
                        AccelerateDSP.packDequantizedDCTBatch(zigzag: UnsafePointer(c.baseAddress!),
                            quantTable: q.baseAddress!, scratch: workspace, blockCount: blocks)
                    }
                    c.baseAddress!.withMemoryRebound(to: Float.self, capacity: count) { output in
                        if dcOnly {
                            AccelerateDSP.writeDCOnlyDCTBatch(values: UnsafePointer(workspace),
                                output: output, blockCount: blocks)
                        } else {
                            AccelerateDSP.inverseDCTBatchPacked(output: output,
                                scratch: workspace, blockCount: blocks)
                        }
                        #expect(expected.indices.allSatisfy { expected[$0].bitPattern == output[$0].bitPattern })
                    }
                }
            }
        }
        #expect(scratch.prefix(3).allSatisfy { $0 == sentinel })
        #expect(scratch.suffix(5).allSatisfy { $0 == sentinel })

        if let precision = clipPrecision {
            var center = Float(1 << (precision - 1)), low: Float = 0, high = Float((1 << precision) - 1)
            expected.withUnsafeMutableBufferPointer { e in
                jliDSP_vsadd(e.baseAddress!, 1, &center, e.baseAddress!, 1, e.count)
                jliDSP_vclip(e.baseAddress!, 1, &low, &high, e.baseAddress!, 1, e.count)
            }
            actual.withUnsafeMutableBufferPointer { a in
                jliDSP_vsadd(a.baseAddress! + 3, 1, &center, a.baseAddress! + 3, 1, expected.count)
                jliDSP_vclip(a.baseAddress! + 3, 1, &low, &high, a.baseAddress! + 3, 1, expected.count)
            }
            #expect(expected.indices.allSatisfy { expected[$0].bitPattern == actual[$0 + 3].bitPattern })
        }
    }

    @Test func everyUnclippedTwelveBitDCAmplitudeKeepsFloatBits() {
        for backend: Backend in [.scalarCPU, .accelerated] {
            NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                // Positive JPEG quantisers are integers. Every DC product that
                // can survive 12-bit level shift/clipping lies in this integer
                // range; larger products and Float conversion are tested below.
                for first in stride(from: -16384, through: 16384, by: 1024) {
                    let count = min(1024, 16385 - first)
                    var coefficients = [Int32](repeating: 0, count: count * 64)
                    for block in 0..<count { coefficients[block * 64] = Int32(first + block) }
                    compare(coefficients, quantiser: 1)
                }
            }
        }
    }

    @Test func amplifiedExtremesTailsAndMixedACKeepExactOutput() {
        let extremes: [Int32] = [.min, -16_777_217, -65535, -16384, -2048, -1, 0,
                                 1, 2048, 16384, 65535, 16_777_217, .max]
        for backend: Backend in [.scalarCPU, .accelerated] {
            NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                for count in [1, 7, 8, 63, 64, 65, 226, 1023, 1024] {
                    for quantiser: Float in [1, 3, 255, 65535] {
                        var coefficients = [Int32](repeating: 0, count: count * 64)
                        for block in 0..<count { coefficients[block * 64] = extremes[block % extremes.count] }
                        compare(coefficients, quantiser: quantiser, clipPrecision: 12)
                    }
                }
                for position in [1, 63, 64 * 1023 + 1, 64 * 1024 - 1] {
                    var coefficients = [Int32](repeating: 0, count: 1024 * 64)
                    for block in 0..<1024 { coefficients[block * 64] = extremes[block % extremes.count] }
                    coefficients[position] = position % 2 == 0 ? 32767 : -32767
                    compare(coefficients, quantiser: 255, clipPrecision: 8)
                }
                // Integer zero plus a positive quantiser must remain positive
                // Float zero, including before the level shift and clipping.
                compare([Int32](repeating: 0, count: 64), quantiser: 65535)
            }
        }
    }
}
