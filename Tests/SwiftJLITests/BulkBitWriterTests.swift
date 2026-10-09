// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct BulkBitWriterTests {
    /// Independent bit-list oracle: concatenate, pad with ones, pack and stuff.
    private func reference(_ bits: [Bool]) -> [UInt8] {
        var padded = bits
        while padded.count % 8 != 0 { padded.append(true) }
        var result: [UInt8] = []
        for start in stride(from: 0, to: padded.count, by: 8) {
            var byte: UInt8 = 0
            for bit in padded[start..<(start + 8)] { byte = (byte << 1) | (bit ? 1 : 0) }
            result.append(byte)
            if byte == 255 { result.append(0) }
        }
        return result
    }

    @Test func alignmentStuffingGrowthAndRestartMatchIndependentBits() {
        for prefix in 0..<8 {
            for length in [0, 1, 2, 31, 4095, 4096, 12287, 12288, 12289] {
                for pattern in 0..<3 {
                    let bytes: [UInt8] = (0..<length).map {
                        pattern == 0 ? 255 : pattern == 1 ? 0 : UInt8(truncatingIfNeeded: $0 * 73 + 19)
                    }
                    var writer = BitWriter(estimatedMaxSize: 64)
                    var bits = [Bool](repeating: true, count: prefix)
                    writer.writeBits(127, count: prefix)
                    bytes.withUnsafeBufferPointer { input in
                        for start in stride(from: 0, to: input.count, by: 12288) {
                            let end = min(start + 12288, input.count)
                            writer.writeUnstuffedBytes(UnsafeBufferPointer(rebasing: input[start..<end]))
                        }
                    }
                    for byte in bytes {
                        for shift in (0..<8).reversed() { bits.append((byte >> shift) & 1 != 0) }
                    }
                    // Also exercise a normal write following a bulk append.
                    writer.writeBits(5, count: 3)
                    bits += [true, false, true]
                    writer.emitRestartMarker(9)
                    var expected = reference(bits) + [0xFF, 0xD1]
                    [UInt8(255), 0, 127].withUnsafeBufferPointer { writer.writeUnstuffedBytes($0) }
                    writer.flush()
                    expected += [255, 0, 0, 127]
                    #expect(writer.data == expected)
                }
            }
        }
    }

    @Test func emptyBulkPreservesPendingBits() {
        var writer = BitWriter(estimatedMaxSize: 64)
        writer.writeBits(0, count: 1)
        writer.writeUnstuffedBytes(UnsafeBufferPointer(start: nil, count: 0))
        writer.flush()
        #expect(writer.data == [127])
    }
}
