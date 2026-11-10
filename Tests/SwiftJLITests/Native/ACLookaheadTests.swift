// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct ACLookaheadTests {
    private func reference(_ reader: inout BitReader, _ table: HuffmanTable,
                           remaining: Int) throws -> (Int, Int32) {
        let symbol = try HuffmanDecoder.decodeSymbol(from: &reader, table: table)
        if symbol == 0 { return (0, 0) }
        if symbol == 0xF0 { return (16, 0) }
        let advance = Int(symbol >> 4) + 1
        // The old decoder stops after a run overflow, without reading magnitude.
        guard advance <= remaining else { return (advance, 0) }
        return (advance, try HuffmanDecoder.decodeValue(from: &reader, category: Int(symbol & 15)))
    }

    @Test func allocationAndCoverageDispatchAreBounded() throws {
        #expect(ACLookahead(table: StandardHuffmanTables.acLuminance, blockCount: 511) == nil)
        let lookup = try #require(ACLookahead(table: StandardHuffmanTables.acLuminance, blockCount: 512))
        #expect(lookup.entries.count * MemoryLayout<UInt32>.size == 32768)
        let long = HuffmanTable(bits: [1] + Array(repeating: 0, count: 15), values: [0x0F])
        #expect(ACLookahead(table: long, blockCount: 65536) == nil)
        let flat = HuffmanTable(bits: [1] + Array(repeating: 0, count: 15), values: [0])
        #expect(ACLookahead(table: flat, blockCount: 65536) == nil)
        let zeros = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [0, 0xF0])
        #expect(ACLookahead(table: zeros, blockCount: 65536) == nil)
    }

    @Test func everyPrefixOffsetAndRunBoundaryMatchesReference() throws {
        let tables = [StandardHuffmanTables.acLuminance, StandardHuffmanTables.acChrominance,
            HuffmanTable(bits: [0, 0, 0, 15] + Array(repeating: 0, count: 12),
                values: (0..<13).map { UInt8($0 << 4) } + [0x01, 0xF0])]
        for table in tables {
            let lookup = try #require(ACLookahead(table: table, blockCount: 512))
            var hits = 0, misses = 0
            for offset in 0..<8 { for prefix in 0..<ACLookahead.count {
                let remaining = prefix % 63 + 1
                var writer = BitWriter(estimatedMaxSize: 32)
                writer.writeBits(0, count: offset)
                writer.writeBits(UInt32(prefix), count: ACLookahead.bits)
                for tail in [UInt32(0xA55A), 0x1234, 0x6789, 0x90AB] {
                    writer.writeBits(tail, count: 16)
                }
                writer.flush()
                var fast = BitReader(data: writer.data), slow = BitReader(data: writer.data)
                _ = try fast.readBits(offset); _ = try slow.readBits(offset)
                let expected = Result { try reference(&slow, table, remaining: remaining) }
                let actual = Result {
                    if let entry = fast.fastDecodeAC(lookup, remaining: remaining) {
                        hits += 1
                        return (Int((entry >> 16) & 0xFF), Int32(Int16(truncatingIfNeeded: entry)))
                    }
                    misses += 1
                    return try reference(&fast, table, remaining: remaining)
                }
                switch (expected, actual) {
                case (.success(let lhs), .success(let rhs)):
                    #expect(lhs.0 == rhs.0 && lhs.1 == rhs.1)
                    #expect(fast.byteOffset == slow.byteOffset)
                    #expect(try fast.readBits(16) == slow.readBits(16))
                case (.failure(let lhs), .failure(let rhs)):
                    #expect(String(describing: lhs) == String(describing: rhs))
                default: Issue.record("Combined AC lookup differs from reference")
                }
            } }
            #expect(hits > 0 && misses > 0)
        }
    }

    @Test func widerPrefetchPreservesLogicalCursorAndMarkerBoundaries() throws {
        let table = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: table, blockCount: 512))
        let tails: [[UInt8]] = [Array(repeating: 0xAA, count: 24), [], [0xFF],
            [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
            [0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xFF, 0, 0xFF, 0xD0]]
        for available in 8...12 { for (tailIndex, tail) in tails.enumerated() {
            var fast = BitReader(data: Array(repeating: 0xAA, count: 8) + tail)
            var referenceReader = fast
            var consume = 64 - available
            while consume > 0 {
                let width = min(consume, 16)
                #expect(try fast.readBits(width) == referenceReader.readBits(width))
                consume -= width
            }
            let expected = try reference(&referenceReader, table, remaining: 63)
            let actual: (Int, Int32)
            if let entry = fast.fastDecodeAC(lookup, remaining: 63) {
                actual = (Int((entry >> 16) & 0xFF), Int32(Int16(truncatingIfNeeded: entry)))
            } else {
                actual = try reference(&fast, table, remaining: 63)
            }
            #expect(actual.0 == expected.0 && actual.1 == expected.1)
            if tailIndex == 0 {
                // This case proves that the additional FF-free prefetch ran.
                #expect(fast.byteOffset > referenceReader.byteOffset)
            } else {
                // A short or FF-containing next word must not be prefetched.
                #expect(fast.byteOffset == referenceReader.byteOffset)
            }
            var fastAligned = fast, referenceAligned = referenceReader
            fastAligned.alignToByte(); referenceAligned.alignToByte()
            #expect(fastAligned.byteOffset == referenceAligned.byteOffset)
            let nextFast = Result { try fast.readBits(16) }
            let nextReference = Result { try referenceReader.readBits(16) }
            switch (nextFast, nextReference) {
            case (.success(let a), .success(let b)): #expect(a == b)
            case (.failure(let a), .failure(let b)):
                #expect(String(describing: a) == String(describing: b))
            default: Issue.record("AC prefetch changed remaining entropy or its error")
            }
        } }
    }
}
