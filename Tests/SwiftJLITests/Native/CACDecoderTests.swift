// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct CACDecoderTests {
    /// Compare the complete current Swift combined path, including physical
    /// prefetch, partial coefficients and the next read after an entropy error.
    private func compare(_ bytes: [UInt8], skipping: Int = 0, table: HuffmanTable,
                         lookup: ACLookahead, kernel: CACKernel) throws -> Bool {
        var reference = BitReader(data: bytes), candidate = reference
        var remaining = skipping
        while remaining > 0 {
            let count = min(16, remaining)
            _ = try reference.readBits(count); _ = try candidate.readBits(count)
            remaining -= count
        }
        var expected = [Int32](repeating: 919, count: 64)
        var guarded = [Int32](repeating: 919, count: 71)
        let lhs = Result {
            try expected.withUnsafeMutableBufferPointer {
                try HuffmanDecoder.decodeAC(from: &reference, table: table, lookup: lookup, into: $0)
            }
        }
        let rhs = Result {
            try guarded.withUnsafeMutableBufferPointer {
                try candidate.decodeAC(using: kernel, into: .init(rebasing: $0[3..<67]))
            }
        }
        var failed = false
        switch (lhs, rhs) {
        case (.success, .success): break
        case (.failure(let a), .failure(let b)):
            failed = true
            #expect(String(describing: a) == String(describing: b))
        default: Issue.record("C leaf changed AC completion or failure")
        }
        #expect(guarded[3..<67].elementsEqual(expected))
        #expect(guarded.prefix(3).allSatisfy { $0 == 919 })
        #expect(guarded.suffix(4).allSatisfy { $0 == 919 })
        #expect(candidate.byteOffset == reference.byteOffset)
        var alignedReference = reference, alignedCandidate = candidate
        alignedReference.alignToByte(); alignedCandidate.alignToByte()
        #expect(alignedCandidate.byteOffset == alignedReference.byteOffset)
        let nextA = Result { try reference.readBits(8) }, nextB = Result { try candidate.readBits(8) }
        switch (nextA, nextB) {
        case (.success(let a), .success(let b)): #expect(a == b)
        case (.failure(let a), .failure(let b)):
            #expect(String(describing: a) == String(describing: b))
        default: Issue.record("C leaf changed the entropy remainder")
        }
        #expect(candidate.byteOffset == reference.byteOffset)
        return failed
    }

    @Test func everyPrefixOffsetAndPartialFailureMatchesSwift() throws {
        let tables = [StandardHuffmanTables.acLuminance, StandardHuffmanTables.acChrominance,
            HuffmanTable(bits: [0, 0, 0, 15] + Array(repeating: 0, count: 12),
                values: (0..<13).map { UInt8($0 << 4) } + [0x01, 0xF0])]
        var successes = 0, failures = 0
        for table in tables {
            let lookup = try #require(ACLookahead(table: table, blockCount: 512))
            try CACKernel.withBorrowed(table: table, lookup: lookup, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                for offset in 0..<8 { for prefix in 0..<ACLookahead.count {
                    var writer = BitWriter(estimatedMaxSize: 32)
                    writer.writeBits(0, count: offset)
                    writer.writeBits(UInt32(prefix), count: ACLookahead.bits)
                    for tail in [UInt32(0xA55A), 0x1234, 0x6789, 0x90AB] { writer.writeBits(tail, count: 16) }
                    writer.flush()
                    if try compare(writer.data, skipping: offset, table: table, lookup: lookup, kernel: kernel) {
                        failures += 1
                    } else { successes += 1 }
                } }
            }
        }
        #expect(successes > 0 && failures > 0)
    }

    @Test func widerRefillAndEveryStuffingMarkerTailMatchSwift() throws {
        let table = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: table, blockCount: 512))
        try CACKernel.withBorrowed(table: table, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            _ = try compare([], table: table, lookup: lookup, kernel: kernel)
            for first in UInt16(0)...255 {
                for tail: [UInt8] in [[], [0], [0xFF], [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
                    Array(repeating: 0, count: 12), Array(repeating: 0xA5, count: 12),
                    [0, 1, 2, 3, 4, 5, 6, 0xFF, 0, 0xFF, 0xD0],
                    [0, 1, 2, 3, 4, 5, 6, 0xFF, 0xD9]] {
                    _ = try compare([UInt8(first)] + tail, table: table, lookup: lookup, kernel: kernel)
                }
            }
            // First bulk-fill64, then consume52...56 bits: the next call starts
            // with8...12 buffered bits, precisely the wider-prefetch boundary.
            for available in 8...12 { for byte in UInt16(0)...255 {
                let bytes = [UInt8](repeating: 0, count: 8) + [UInt8(byte)] +
                    [0xA5, 0x5A, 0x12, 0x34, 0xFF, 0, 0xFF, 0xD0]
                _ = try compare(bytes, skipping: 64 - available, table: table, lookup: lookup, kernel: kernel)
            } }
        }
    }

    @Test func allMagnitudeCategoriesAndRestartsPreserveUnalignedState() throws {
        let table = HuffmanTable(bits: [0, 0, 0, 16] + Array(repeating: 0, count: 12),
                                 values: (1...15).map(UInt8.init) + [0])
        let lookup = try #require(ACLookahead(table: table, blockCount: 512))
        var blocks = [[Int32](repeating: 0, count: 64)]
        for category in 1...15 {
            var block = [Int32](repeating: 0, count: 64)
            for index in 1..<64 { block[index] = Int32((1 << category) - 1) * (index % 2 == 0 ? 1 : -1) }
            blocks.append(block)
        }
        try CACKernel.withBorrowed(table: table, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            for offset in 0..<8 {
                var writer = BitWriter()
                writer.writeBits(0, count: offset)
                for block in blocks { HuffmanEncoder.encodeAC(block, table: table, writer: &writer) }
                writer.emitRestartMarker(3); writer.writeBits(0x5A, count: 8); writer.flush()
                var reader = BitReader(data: writer.data)
                _ = try reader.readBits(offset)
                for expected in blocks {
                    var output = [Int32](repeating: 919, count: 64)
                    try output.withUnsafeMutableBufferPointer { try reader.decodeAC(using: kernel, into: $0) }
                    #expect(output == expected)
                }
                try reader.skipRestartMarker(expectedIndex: 3)
                #expect(try reader.readBits(8) == 0x5A)
            }
        }
    }

    @Test func disabledOrMissingLookupRetainsSwiftAndBadDestinationDoesNotWrite() throws {
        let table = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: table, blockCount: 512))
        CACKernel.withBorrowed(table: table, lookup: lookup, enabled: false) { #expect($0 == nil) }
        CACKernel.withBorrowed(table: table, lookup: nil, enabled: true) { #expect($0 == nil) }
        try CACKernel.withBorrowed(table: table, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            for count in [0, 63, 65] {
                var reader = BitReader(data: [0xAA, 0xBB])
                var output = [Int32](repeating: 919, count: count)
                #expect(throws: JLIError.self) {
                    try output.withUnsafeMutableBufferPointer { try reader.decodeAC(using: kernel, into: $0) }
                }
                #expect(output.allSatisfy { $0 == 919 })
                #expect(reader.byteOffset == 0)
            }
        }
    }

    @Test func runOverflowAndZRLStopWithoutConsumingFollowingBits() throws {
        let table = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: table, blockCount: 512))
        try CACKernel.withBorrowed(table: table, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            for offset in 0..<8 { for zrl in [false, true] {
                var writer = BitWriter()
                writer.writeBits(0, count: offset)
                if zrl {
                    // Four ZRL symbols pass the final coefficient; no fifth
                    // symbol is read and no error is introduced.
                    let code = table.encodingTable[0xF0]
                    for _ in 0..<4 { writer.writeBits(UInt32(code.code), count: Int(code.length)) }
                } else {
                    let one = table.encodingTable[0x01]
                    for _ in 0..<62 {
                        writer.writeBits(UInt32(one.code), count: Int(one.length))
                        writer.writeBits(1, count: 1)
                    }
                    // At index63, run1 exceeds the block. The combined entry
                    // must miss before consuming its one magnitude bit.
                    let overflow = table.encodingTable[0x11]
                    writer.writeBits(UInt32(overflow.code), count: Int(overflow.length))
                }
                writer.writeBits(0x5A, count: 8); writer.flush()
                var reader = BitReader(data: writer.data)
                _ = try reader.readBits(offset)
                var output = [Int32](repeating: 919, count: 64)
                try output.withUnsafeMutableBufferPointer { try reader.decodeAC(using: kernel, into: $0) }
                #expect(output[0] == 0 && output[63] == 0)
                #expect(output[1..<63].allSatisfy { $0 == (zrl ? 0 : 1) })
                #expect(try reader.readBits(8) == 0x5A)
                _ = try compare(writer.data, skipping: offset, table: table, lookup: lookup, kernel: kernel)
            } }
        }
    }
}
