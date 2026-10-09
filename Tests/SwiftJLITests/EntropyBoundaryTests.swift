// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct EntropyBoundaryTests {
    @Test func stuffedPairsRestartsAndMarkersCrossCheckBoundaries() throws {
        for offset in [0, 1, 4094, 4095, 4096, 4097, 8191] {
            for next: UInt8 in [0, 208, 215, 216, 217, 255] {
                var bytes = [UInt8](repeating: 17, count: offset + 6000)
                bytes[offset] = 255; bytes[offset + 1] = next
                bytes[bytes.count - 2] = 255; bytes[bytes.count - 1] = 217
                let expected = next == 0 || (208...215).contains(next) ? bytes.count - 2 : offset
                #expect(try JPEGEntropyBoundary.find(in: bytes, from: 0) == expected)
                #expect(try JPEGEntropyBoundary.find(in: bytes, from: offset) == expected)
            }
        }
        #expect(try JPEGEntropyBoundary.find(in: [], from: 0) == 0)
        #expect(try JPEGEntropyBoundary.find(in: [1, 255], from: 0) == 1)
        #expect(try JPEGEntropyBoundary.find(in: [255, 0], from: 0) == 2)
        #expect(throws: CodecError.self) { try JPEGEntropyBoundary.find(in: [1], from: -1) }
        #expect(throws: CodecError.self) { try JPEGEntropyBoundary.find(in: [1], from: 2) }
    }

    @Test func agreesWithBytewiseReferenceAcrossSyntheticInputs() throws {
        var state: UInt64 = 17
        for length in [1, 7, 4095, 4096, 4097, 10000] {
            for _ in 0..<20 {
                let bytes: [UInt8] = (0..<length).map { _ in
                    state = state &* 6364136223846793005 &+ 1
                    return UInt8(truncatingIfNeeded: state >> 32)
                }
                for start in [0, length / 2, length] {
                    var expected = start
                    while expected < bytes.count {
                        if bytes[expected] != 255 { expected += 1; continue }
                        if expected + 1 == bytes.count { break }
                        let next = bytes[expected + 1]
                        if next == 0 || (208...215).contains(next) { expected += 2 } else { break }
                    }
                    #expect(try JPEGEntropyBoundary.find(in: bytes, from: start) == expected)
                }
            }
        }
    }

    @Test func markerFreePayloadStillChecksDeadline() throws {
        let bytes = [UInt8](repeating: 1, count: 20000)
        #expect(throws: CodecError.self) {
            try NativeOperation.$current.withValue(.init(seconds: Double.leastNonzeroMagnitude)) {
                try JPEGEntropyBoundary.find(in: bytes, from: 0)
            }
        }
    }

    @Test func greyscaleWriterPreservesRoundingEndianPaddingAndFinitePolicy() throws {
        let values: [Float] = [-1, 0.5, 1.5, 255.5, 4095.5]
        for precision in [8, 12] {
            for bps in precision == 8 ? [1, 2, 4] : [2, 4] {
                let row = values.count * bps + 8
                var bytes = [UInt8](repeating: 0xAB, count: row)
                try bytes.withUnsafeMutableBytes { raw in
                    try SharedDCTStorage.write([(values, values.count, 1)], width: values.count, height: 1,
                        precision: precision, floatOutput: bps == 4,
                        into: .init(bytes: raw, rowBytes: row, bytesPerSample: bps))
                }
                for (i, sample) in values.enumerated() {
                    let expected = bps == 4 ? sample.bitPattern
                        : UInt32(max(0, min(Float((1 << precision) - 1), sample)).rounded(.toNearestOrAwayFromZero))
                    for byte in 0..<bps { #expect(bytes[i * bps + byte] == UInt8(truncatingIfNeeded: expected >> (byte * 8))) }
                }
                #expect(bytes.suffix(8).allSatisfy { $0 == 0xAB })
                for value in [Float.nan, .infinity, -.infinity] {
                    #expect(throws: JLIError.self) {
                        try bytes.withUnsafeMutableBytes { raw in
                            try SharedDCTStorage.write([([value], 1, 1)], width: 1, height: 1,
                                precision: precision, floatOutput: bps == 4,
                                into: .init(bytes: raw, rowBytes: row, bytesPerSample: bps))
                        }
                    }
                }
            }
        }
    }
}
