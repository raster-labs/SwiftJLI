// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct LosslessLookaheadTests {
    private func reference(_ reader: inout BitReader, _ table: HuffmanTable) throws -> Int32 {
        let category = Int(try HuffmanDecoder.decodeSymbolBitByBit(from: &reader, table: table))
        return category == 16 ? -32768 : try HuffmanDecoder.decodeValue(from: &reader, category: category)
    }

    @Test func allocationAndLongMagnitudeDispatchAreBounded() throws {
        let short = HuffmanTable(bits: [1, 1, 1] + Array(repeating: 0, count: 13), values: [0, 1, 2])
        #expect(LosslessLookahead(table: short, sampleCount: 16383) == nil)
        let combined = try #require(LosslessLookahead(table: short, sampleCount: 16384))
        #expect(combined.entries.count * MemoryLayout<UInt32>.size == 32768)
        let long = HuffmanTable(bits: [1] + Array(repeating: 0, count: 15), values: [15])
        #expect(LosslessLookahead(table: long, sampleCount: 4_194_304) == nil)
        let uniform = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [7, 16])
        #expect(LosslessLookahead(table: uniform, sampleCount: 4_194_304) == nil)
    }

    @Test func everyPrefixAndBitOffsetMatchesBitwiseReference() throws {
        let tables = [
            StandardHuffmanTables.dcLuminance,
            HuffmanTable(bits: [1, 1, 1, 1] + Array(repeating: 0, count: 12), values: [0, 1, 1, 2]),
            HuffmanTable(bits: [1, 1, 1] + Array(repeating: 0, count: 13), values: [0, 16, 1]),
            HuffmanTable(bits: [1, 1, 1, 1] + Array(repeating: 0, count: 12), values: [9, 0, 15, 1]),
            HuffmanTable(bits: [1, 1, 1, 1] + Array(repeating: 0, count: 12), values: [0, 1, 2, 255])
        ]
        for table in tables {
            let combined = try #require(LosslessLookahead(table: table, sampleCount: 16384))
            var hits = 0, misses = 0
            for offset in 0..<8 {
                for prefix in 0..<LosslessLookahead.count {
                    var writer = BitWriter(estimatedMaxSize: 32)
                    writer.writeBits(0, count: offset)
                    writer.writeBits(UInt32(prefix), count: 13)
                    for tail in [UInt32(0xA55A), 0x1234, 0x6789, 0x90AB] {
                        writer.writeBits(tail, count: 16)
                    }
                    writer.flush()
                    var fast = BitReader(data: writer.data), slow = BitReader(data: writer.data)
                    _ = try fast.readBits(offset); _ = try slow.readBits(offset)
                    let expected = Result { try reference(&slow, table) }
                    let actual = Result {
                        if let difference = fast.fastDecodeLosslessDifference(combined) {
                            hits += 1
                            return difference
                        }
                        misses += 1
                        return try reference(&fast, table)
                    }
                    switch (expected, actual) {
                    case (.success(let lhs), .success(let rhs)):
                        #expect(lhs == rhs)
                        #expect(try fast.readBits(16) == slow.readBits(16))
                    case (.failure(let lhs), .failure(let rhs)):
                        #expect(String(describing: lhs) == String(describing: rhs))
                    default: Issue.record("Combined lookup differs from bitwise decode")
                    }
                }
            }
            #expect(hits > 0 && misses > 0)
        }
    }

    @Test(arguments: [2, 8, 12, 16])
    func largeScansPreservePredictorsRestartsPointTransformsAndPadding(bits: Int) throws {
        let width = 129, height = 129, bps = bits <= 8 ? 1 : 2, mask = (1 << bits) - 1
        var source: [UInt8] = []
        for y in 0..<height { for x in 0..<width {
            let value = (x * 17 + y * 31 + x * y % 257) & mask
            source.append(UInt8(truncatingIfNeeded: value))
            if bps == 2 { source.append(UInt8(value >> 8)) }
        } }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: bps == 1 ? .uint8 : .uint16, colorModel: .grayscale, data: source)
        var lookupScans = 0
        for predictor in 1...7 { for pt in [0, min(2, bits - 1)] { for rows in [0, 3] {
            var configuration = JLIEncoderConfiguration(lossless: true)
            configuration.losslessPrecision = bits; configuration.losslessPredictor = predictor
            configuration.losslessPointTransform = pt; configuration.restartInterval = width * rows
            let jpeg = try JLIEncoder().encode(image, configuration: configuration)
            let expected = try JLIDecoder().decode(from: jpeg).data
            var parser = MarkerReader(data: jpeg)
            let parsed = try parser.parse()
            let table = try #require(parsed.scans.first?.dcTables[0])
            if LosslessLookahead(table: table, sampleCount: width * height) != nil { lookupScans += 1 }
            let stride = width * bps + 5, offset = 3
            var storage = [UInt8](repeating: 0xA5, count: offset + height * stride + 7)
            try storage.withUnsafeMutableBytes { raw in
                try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                    bytes: .init(rebasing: raw[offset..<(offset + height * stride)]),
                    rowBytes: stride, bytesPerSample: bps))
            }
            for y in 0..<height {
                let start = offset + y * stride
                #expect(storage[start..<(start + width * bps)]
                    .elementsEqual(expected[(y * width * bps)..<((y + 1) * width * bps)]))
                #expect(storage[(start + width * bps)..<(start + stride)].allSatisfy { $0 == 0xA5 })
            }
            #expect(storage.prefix(offset).allSatisfy { $0 == 0xA5 })
            #expect(storage.suffix(7).allSatisfy { $0 == 0xA5 })
        } } }
        #expect(lookupScans > 0)
    }

    @Test func lookupRejectsInvalidStorageBeforeWriting() throws {
        let width = 129, height = 129
        let source = (0..<(width * height)).map { index in
            UInt8(truncatingIfNeeded: index * 17 + (index / width) * 31)
        }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: .uint8, colorModel: .grayscale, data: source)
        let jpeg = try JLIEncoder().encode(image, configuration: .init(lossless: true))
        var parser = MarkerReader(data: jpeg)
        let parsed = try parser.parse()
        let table = try #require(parsed.scans.first?.dcTables[0])
        #expect(LosslessLookahead(table: table, sampleCount: width * height) != nil)
        for (bps, stride, count) in [
            (0, width, width * height), (3, width * 3, width * height * 3),
            (1, width - 1, width * height), (2, width * 2 - 1, width * height * 2),
            (1, width, width * height - 1), (2, width * 2, width * height * 2 - 1)
        ] {
            var storage = [UInt8](repeating: 0xA5, count: count)
            #expect(throws: JLIError.self) {
                try storage.withUnsafeMutableBytes { raw in
                    try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                        bytes: raw, rowBytes: stride, bytesPerSample: bps))
                }
            }
            #expect(storage.allSatisfy { $0 == 0xA5 })
        }
    }
}
