// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct ScopedACDecoderTests {
    private func pointerDecode(_ reader: inout BitReader, table: HuffmanTable,
                               lookup: ACLookahead? = nil, output: inout [Int32]) throws {
        try output.withUnsafeMutableBufferPointer { storage in
            let block = UnsafeMutableBufferPointer(rebasing: storage[3..<67])
            if let lookup {
                try HuffmanDecoder.decodeAC(from: &reader, table: table, lookup: lookup, into: block)
            } else {
                try HuffmanDecoder.decodeAC(from: &reader, table: table, into: block)
            }
        }
    }

    @Test(arguments: [false, true])
    func coefficientsAndRestartPositionMatchArrayReference(combined: Bool) throws {
        var blocks = [[Int32](repeating: 0, count: 64)]
        for category in 1...15 {
            for step in [1, 3, 17, 31, 62] {
                var block = [Int32](repeating: 0, count: 64)
                for index in stride(from: 1, to: 64, by: step) {
                    block[index] = Int32((1 << category) - 1) * (index % 2 == 0 ? 1 : -1)
                }
                blocks.append(block)
            }
        }
        var frequencies = [Int](repeating: 0, count: 256)
        for block in blocks { HuffmanEncoder.countAC(block, freq: &frequencies) }
        let table = HuffmanTableBuilder.build(frequencies: frequencies, fallback: StandardHuffmanTables.acLuminance)
        let lookup = combined ? ACLookahead(table: table, blockCount: 512) : nil
        for offset in 0..<8 {
            var writer = BitWriter()
            writer.writeBits(0, count: offset)
            for block in blocks { HuffmanEncoder.encodeAC(block, table: table, writer: &writer) }
            writer.emitRestartMarker(0)
            writer.writeBits(0x5A, count: 8)
            writer.flush()
            var reference = BitReader(data: writer.data), scoped = BitReader(data: writer.data)
            _ = try reference.readBits(offset); _ = try scoped.readBits(offset)
            for block in blocks {
                var expected = [Int32](repeating: 919, count: 64)
                var actual = [Int32](repeating: 919, count: 71)
                try HuffmanDecoder.decodeAC(from: &reference, table: table, into: &expected)
                try pointerDecode(&scoped, table: table, lookup: lookup, output: &actual)
                #expect(expected == block)
                #expect(Array(actual[3..<67]) == expected)
                #expect(actual.prefix(3).allSatisfy { $0 == 919 })
                #expect(actual.suffix(4).allSatisfy { $0 == 919 })
            }
            try reference.skipRestartMarker(expectedIndex: 0)
            try scoped.skipRestartMarker(expectedIndex: 0)
            #expect(reference.byteOffset == scoped.byteOffset)
            #expect(try reference.readBits(8) == 0x5A)
            #expect(try scoped.readBits(8) == 0x5A)
        }
    }

    @Test(arguments: [false, true])
    func malformedAndTruncatedEntropyPreserveReferenceBehaviour(combined: Bool) throws {
        // Every byte value exercises EOB, ZRL, zero categories, overshooting
        // zero runs, long codes, stuffing and markers under a real AC table.
        let table = StandardHuffmanTables.acLuminance
        let lookup = combined ? try #require(ACLookahead(table: table, blockCount: 512)) : nil
        for first in UInt16(0)...255 {
            for tail: [UInt8] in [[], [0], [0xFF], [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
                                  Array(repeating: 0, count: 12), Array(repeating: 0xA5, count: 12),
                                  [0, 1, 2, 3, 4, 5, 6, 0xFF, 0, 0xFF, 0xD0],
                                  [0, 1, 2, 3, 4, 5, 6, 0xFF, 0xD9]] {
                let data = [UInt8(first)] + tail
                var reference = BitReader(data: data), scoped = BitReader(data: data)
                var expected = [Int32](repeating: 919, count: 64)
                var actual = [Int32](repeating: 919, count: 71)
                let lhs = Result { try HuffmanDecoder.decodeAC(from: &reference, table: table, into: &expected) }
                let rhs = Result { try pointerDecode(&scoped, table: table, lookup: lookup, output: &actual) }
                switch (lhs, rhs) {
                case (.success, .success): break
                case (.failure(let left), .failure(let right)):
                    #expect(String(describing: left) == String(describing: right))
                default: Issue.record("Scoped AC error behaviour differs from array reference")
                }
                #expect(Array(actual[3..<67]) == expected)
                #expect(actual.prefix(3).allSatisfy { $0 == 919 })
                #expect(actual.suffix(4).allSatisfy { $0 == 919 })
                #expect(reference.byteOffset == scoped.byteOffset)
            }
        }
    }

    @Test func invalidDestinationIsRejectedBeforeWriting() {
        var reader = BitReader(data: [])
        var output = [Int32](repeating: 919, count: 63)
        #expect(throws: JLIError.self) {
            try output.withUnsafeMutableBufferPointer {
                try HuffmanDecoder.decodeAC(from: &reader, table: StandardHuffmanTables.acLuminance, into: $0)
            }
        }
        #expect(output.allSatisfy { $0 == 919 })
    }
}
