// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct LosslessDifferenceTests {
    private func reference(_ reader: inout BitReader, table: HuffmanTable) throws -> Int32 {
        let category = Int(try HuffmanDecoder.decodeSymbolBitByBit(from: &reader, table: table))
        if category == 16 { return -32768 }
        return try HuffmanDecoder.decodeValue(from: &reader, category: category)
    }

    private func fused(_ reader: inout BitReader, table: HuffmanTable) throws -> Int32 {
        if let value = reader.fastDecodeLosslessDifference(table) { return value }
        return try reference(&reader, table: table)
    }

    @Test func everyMagnitudeAtEveryBitOffsetMatchesBitwiseReference() throws {
        for category in 0...16 {
            let table = HuffmanTable(bits: [1] + [UInt8](repeating: 0, count: 15), values: [UInt8(category)])
            let magnitudeCount = category == 0 || category == 16 ? 16 : 1 << category
            for offset in 0..<8 {
                var writer = BitWriter()
                writer.writeBits(0, count: offset)
                for magnitude in 0..<magnitudeCount {
                    writer.writeBits(0, count: 1)
                    if category > 0, category < 16 { writer.writeBits(UInt32(magnitude), count: category) }
                }
                writer.emitRestartMarker(0)
                writer.writeBits(0x5A, count: 8)
                writer.flush()
                var fast = BitReader(data: writer.data), slow = BitReader(data: writer.data)
                _ = try fast.readBits(offset); _ = try slow.readBits(offset)
                var hits = 0
                for magnitude in 0..<magnitudeCount {
                    let expected: Int32 = category == 0 ? 0 : category == 16 ? -32768
                        : magnitude < (1 << (category - 1)) ? Int32(magnitude - ((1 << category) - 1)) : Int32(magnitude)
                    let actual: Int32
                    if let value = fast.fastDecodeLosslessDifference(table) { actual = value; hits += 1 }
                    else { actual = try reference(&fast, table: table) }
                    #expect(actual == expected)
                    #expect(try reference(&slow, table: table) == expected)
                }
                if category == 0 || category >= 4 { #expect(hits > 0) }
                try fast.skipRestartMarker(expectedIndex: 0)
                try slow.skipRestartMarker(expectedIndex: 0)
                #expect(fast.byteOffset == slow.byteOffset)
                #expect(try fast.readBits(8) == 0x5A)
                #expect(try slow.readBits(8) == 0x5A)
            }
        }
    }

    @Test func longCodesTruncationMarkersAndInvalidCategoriesUseFallback() throws {
        for length in [1, 8, 9, 16] {
            for category in [0, 1, 8, 15, 16, 17, 31, 255] {
                var lengths = [UInt8](repeating: 0, count: 16)
                lengths[length - 1] = 1
                let table = HuffmanTable(bits: lengths, values: [UInt8(category)])
                var writer = BitWriter()
                writer.writeBits(0, count: length)
                if category > 0, category < 16 { writer.writeBits((1 << category) - 1, count: category) }
                writer.flush()
                let encoded = writer.data
                // Every possible truncation, including a terminal stuffed FF,
                // followed by EOF, restart, or end-of-image marker.
                for end in 0...encoded.count {
                    for tail: [UInt8] in [[], [0xFF], [0xFF, 0xD0], [0xFF, 0xD9]] {
                        let data = Array(encoded.prefix(end)) + tail
                        var fast = BitReader(data: data), slow = BitReader(data: data)
                        let expected = Result { try reference(&slow, table: table) }
                        let actual = Result { try fused(&fast, table: table) }
                        switch (expected, actual) {
                        case (.success(let lhs), .success(let rhs)): #expect(lhs == rhs)
                        case (.failure(let lhs), .failure(let rhs)):
                            #expect(String(describing: lhs) == String(describing: rhs))
                        default: Issue.record("Fast/fallback result differs at category \(category), length \(length), cutoff \(end)")
                        }
                    }
                }
            }
        }
    }
}
