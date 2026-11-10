// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct TinyDCCentreTests {
    private func compare(_ dc: [Int32], quantiser: Float, precision: Int) throws {
        // This is the unchanged larger compact path: stored reconstruction,
        // then its established DSP addition and clipping on the chosen backend.
        var expected = [Float](repeating: 0, count: dc.count)
        dc.withUnsafeBufferPointer { input in
            expected.withUnsafeMutableBufferPointer { output in
                DCOnlyGreyscaleDecoder.reconstruct(input.baseAddress!, quantiser: quantiser,
                    into: output.baseAddress!, blockCount: dc.count)
                var centre = Float(1 << (precision - 1)), low: Float = 0
                var high = Float((1 << precision) - 1)
                jliDSP_vsadd(output.baseAddress!, 1, &centre, output.baseAddress!, 1, output.count)
                jliDSP_vclip(output.baseAddress!, 1, &low, &high, output.baseAddress!, 1, output.count)
            }
        }
        let sentinel: Float = -123456
        var guarded = [Float](repeating: sentinel, count: dc.count + 8)
        try dc.withUnsafeBufferPointer { input in
            try guarded.withUnsafeMutableBufferPointer { storage in
                try DCOnlyGreyscaleDecoder.reconstructTinyCentred(input, quantiser: quantiser,
                    precision: precision, into: .init(rebasing: storage[3..<(3 + dc.count)]))
            }
        }
        #expect(expected.indices.allSatisfy { expected[$0].bitPattern == guarded[$0 + 3].bitPattern })
        #expect(guarded.prefix(3).allSatisfy { $0 == sentinel })
        #expect(guarded.suffix(5).allSatisfy { $0 == sentinel })
    }

    @Test(arguments: [8, 12])
    func everyAdmittedDCAmplitudePreservesShiftedClippedFloatBits(precision: Int) throws {
        let bound = 1 << (precision + 2)
        for backend: Backend in [.scalarCPU, .accelerated] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                for first in stride(from: -bound, through: bound, by: 16) {
                    let count = min(16, bound - first + 1)
                    try compare((0..<count).map { Int32(first + $0) }, quantiser: 1, precision: precision)
                }
            }
        }
    }

    @Test(arguments: [8, 12], [1, 9, 16])
    func amplifiedExtremesAndTinyTailsPreserveFloatBitsAndGuards(precision: Int, count: Int) throws {
        let extremes: [Int32] = [.min, -16_777_217, -65535, -16384, -1024, -1, 0,
                                 1, 1024, 16384, 65535, 16_777_217, .max]
        for backend: Backend in [.scalarCPU, .accelerated] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                for quantiser: Float in [1, 3, 17, 255, 65535] {
                    for offset in extremes.indices {
                        try compare((0..<count).map { extremes[($0 + offset) % extremes.count] },
                            quantiser: quantiser, precision: precision)
                    }
                }
            }
        }
    }

    @Test func malformedTinyExtentsAndPrecisionRejectBeforeWriting() {
        for (count, outputCount, precision) in [(0, 0, 8), (17, 17, 8), (16, 15, 8),
                                               (16, 17, 12), (1, 1, 7), (1, 1, 13)] {
            let input = [Int32](repeating: 1, count: count)
            var output = [Float](repeating: -123456, count: outputCount + 8)
            #expect(throws: JLIError.self) {
                try input.withUnsafeBufferPointer { dc in
                    try output.withUnsafeMutableBufferPointer { storage in
                        try DCOnlyGreyscaleDecoder.reconstructTinyCentred(dc, quantiser: 1,
                            precision: precision,
                            into: .init(rebasing: storage[3..<(3 + outputCount)]))
                    }
                }
            }
            #expect(output.allSatisfy { $0 == -123456 })
        }
    }
}
