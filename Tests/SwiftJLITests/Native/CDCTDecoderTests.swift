// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct CDCTDecoderTests {
    /// The reference spells out the existing producer's exact mutation order.
    /// In particular a DC failure leaves the destination untouched, while an
    /// AC failure occurs after previousDC changes and after AC clears the slot.
    private func compare(_ bytes: [UInt8], skipping: Int = 0, previousDC: Int32 = 0,
                         precision: Int, dc: HuffmanTable, ac: HuffmanTable,
                         lookup: ACLookahead, kernel: CDCTKernel) throws -> String? {
        var reference = BitReader(data: bytes), candidate = reference
        _ = try reference.readBits(skipping); _ = try candidate.readBits(skipping)
        var referenceDC = previousDC, candidateDC = previousDC
        var expected = [Int32](repeating: 919, count: 64)
        var guarded = [Int32](repeating: 919, count: 71)
        let lhs = Result {
            let difference = try HuffmanDecoder.decodeDC(from: &reference, table: dc)
            let value = Int64(referenceDC) + Int64(difference)
            guard abs(value) <= (1 << (precision + 2)) else {
                throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
            }
            referenceDC = Int32(value)
            try expected.withUnsafeMutableBufferPointer {
                try HuffmanDecoder.decodeAC(from: &reference, table: ac, lookup: lookup, into: $0)
            }
            expected[0] = referenceDC
        }
        let rhs = Result {
            try guarded.withUnsafeMutableBufferPointer {
                try candidate.decodeDCT(using: kernel, previousDC: &candidateDC,
                    precision: precision, into: .init(rebasing: $0[3..<67]))
            }
        }
        var failure: String?
        switch (lhs, rhs) {
        case (.success, .success): break
        case (.failure(let a), .failure(let b)):
            failure = String(describing: a)
            #expect(String(describing: a) == String(describing: b))
        default: Issue.record("C DC+AC leaf changed block completion or failure")
        }
        #expect(candidateDC == referenceDC)
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
        default: Issue.record("C DC+AC leaf changed the entropy remainder")
        }
        #expect(candidate.byteOffset == reference.byteOffset)
        return failure
    }

    @Test(arguments: [8, 12])
    func everyPrefixOffsetAndFailureStateMatchesSwift(precision: Int) throws {
        let tables = [(StandardHuffmanTables.dcLuminance, StandardHuffmanTables.acLuminance),
                      (StandardHuffmanTables.dcChrominance, StandardHuffmanTables.acChrominance)]
        var successes = 0, failures = 0
        for (dc, ac) in tables {
            let lookup = try #require(ACLookahead(table: ac, blockCount: 512))
            try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                for offset in 0..<8 { for prefix in 0..<ACLookahead.count {
                    var writer = BitWriter(estimatedMaxSize: 32)
                    writer.writeBits(0, count: offset)
                    writer.writeBits(UInt32(prefix), count: ACLookahead.bits)
                    for tail in [UInt32(0xA55A), 0x1234, 0x6789, 0x90AB] { writer.writeBits(tail, count: 16) }
                    writer.flush()
                    if try compare(writer.data, skipping: offset, precision: precision,
                        dc: dc, ac: ac, lookup: lookup, kernel: kernel) == nil { successes += 1 }
                    else { failures += 1 }
                } }
            }
        }
        #expect(successes > 0 && failures > 0)
    }

    @Test(arguments: [8, 12])
    func dcCategoriesBoundsAndInvalidWidthsPreserveMutationOrder(precision: Int) throws {
        let ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 512))
        let bound = Int32(1 << (precision + 2))
        for category in Array(0...16) + [17, 31, 255] {
            let dc = HuffmanTable(bits: [1] + Array(repeating: 0, count: 15), values: [UInt8(category)])
            try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                let magnitudes = category == 0 || category > 16 ? [0]
                    : [0, 1 << (category - 1), (1 << category) - 1]
                for offset in 0..<8 { for magnitude in magnitudes {
                    var writer = BitWriter()
                    writer.writeBits(0, count: offset); writer.writeBits(0, count: 1)
                    if category <= 16 { writer.writeBits(UInt32(magnitude), count: category) }
                    var block = [Int32](repeating: 0, count: 64)
                    block[1] = 1; block[62] = -2
                    HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
                    writer.writeBits(0x5A, count: 8); writer.flush()
                    for previous in [Int32(0), bound, -bound, Int32.max, Int32.min] {
                        let failure = try compare(writer.data, skipping: offset, previousDC: previous,
                            precision: precision, dc: dc, ac: ac, lookup: lookup, kernel: kernel)
                        if category > 16 {
                            #expect(failure?.contains("invalid bit-read width \(category)") == true)
                        }
                    }
                } }
            }
        }
    }

    @Test func markerAndTruncationErrorsPreservePartialDCPredictorAndAC() throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 512))
        try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            _ = try compare([], precision: 12, dc: dc, ac: ac, lookup: lookup, kernel: kernel)
            for first in UInt16(0)...255 {
                for tail: [UInt8] in [[], [0], [0xFF], [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
                    Array(repeating: 0, count: 12), Array(repeating: 0xA5, count: 12),
                    [0, 1, 2, 3, 4, 5, 6, 0xFF, 0, 0xFF, 0xD0]] {
                    _ = try compare([UInt8(first)] + tail, previousDC: 19, precision: 12,
                        dc: dc, ac: ac, lookup: lookup, kernel: kernel)
                }
            }
            var writer = BitWriter()
            var block = [Int32](repeating: 511, count: 64)
            block[0] = 17
            HuffmanEncoder.encodeDC(block[0], table: dc, writer: &writer)
            HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
            writer.flush()
            for end in 0...writer.data.count {
                _ = try compare(Array(writer.data.prefix(end)), precision: 12,
                    dc: dc, ac: ac, lookup: lookup, kernel: kernel)
            }
        }
    }

    @Test(arguments: [8, 12])
    func combinedBlocksKeepDCBoundsAcrossUnalignedRestarts(precision: Int) throws {
        let dc = HuffmanTable(bits: [0, 0, 0, 0, 17] + Array(repeating: 0, count: 11),
                             values: (0...16).map(UInt8.init))
        let ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 512))
        let bound = Int32(1 << (precision + 2))
        try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            for offset in 0..<8 {
                var writer = BitWriter(), previous: Int32 = 0, blocks: [[Int32]] = []
                writer.writeBits(0, count: offset)
                for index in 0..<20 {
                    if index > 0 && index % 3 == 0 { writer.emitRestartMarker((index / 3 - 1) & 7); previous = 0 }
                    var block = [Int32](repeating: 0, count: 64)
                    block[0] = [-bound, bound, bound - 1, 0][index % 4]
                    block[1 + index % 62] = index % 2 == 0 ? 17 : -3
                    HuffmanEncoder.encodeDC(block[0] - previous, table: dc, writer: &writer)
                    HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
                    previous = block[0]; blocks.append(block)
                }
                writer.emitRestartMarker(7); writer.writeBits(0x5A, count: 8); writer.flush()
                var reader = BitReader(data: writer.data), prediction: Int32 = 0
                _ = try reader.readBits(offset)
                for (index, expected) in blocks.enumerated() {
                    if index > 0 && index % 3 == 0 { try reader.skipRestartMarker(expectedIndex: (index / 3 - 1) & 7); prediction = 0 }
                    var output = [Int32](repeating: 919, count: 64)
                    try output.withUnsafeMutableBufferPointer {
                        try reader.decodeDCT(using: kernel, previousDC: &prediction, precision: precision, into: $0)
                    }
                    #expect(output == expected && prediction == expected[0])
                }
                try reader.skipRestartMarker(expectedIndex: 7)
                #expect(try reader.readBits(8) == 0x5A)
            }
        }
    }

    @Test func invalidDestinationAndPrecisionRejectBeforeReadingOrWriting() throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 512))
        CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: false) { #expect($0 == nil) }
        try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            for (count, precision) in [(0, 8), (63, 8), (65, 12), (64, 7), (64, 13), (64, Int.max)] {
                var reader = BitReader(data: [0xAA, 0xBB]), previous: Int32 = 17
                var output = [Int32](repeating: 919, count: count)
                #expect(throws: JLIError.self) {
                    try output.withUnsafeMutableBufferPointer {
                        try reader.decodeDCT(using: kernel, previousDC: &previous, precision: precision, into: $0)
                    }
                }
                #expect(output.allSatisfy { $0 == 919 } && previous == 17)
                #expect(reader.byteOffset == 0)
            }
        }
    }
}
