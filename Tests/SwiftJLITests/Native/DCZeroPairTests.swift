// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct DCZeroPairTests {
    private let dc = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [0, 1])
    private let ac = HuffmanTable(bits: [1, 0, 2] + Array(repeating: 0, count: 13), values: [0, 0xF0, 0x10])

    private func entropy(blocks: Int, interval: Int, offset: Int) -> [UInt8] {
        var writer = BitWriter()
        writer.writeBits(0, count: offset)
        for index in 0..<blocks {
            if interval > 0, index > 0, index % interval == 0 {
                writer.emitRestartMarker((index / interval - 1) & 7)
            }
            let difference: Int32 = index % 31 == 0 ? (index / 31 % 2 == 0 ? 1 : -1) : 0
            HuffmanEncoder.encodeDC(difference, table: dc, writer: &writer)
            let symbol: UInt8 = index % 29 == 0 ? 0xF0 : index % 47 == 0 ? 0x10 : 0
            let code = ac.encodingTable[Int(symbol)]
            var coefficient = 1
            while coefficient < 64 {
                writer.writeBits(UInt32(code.code), count: Int(code.length))
                if symbol == 0 { break }
                coefficient += symbol == 0xF0 ? 16 : 2
            }
        }
        writer.emitRestartMarker(3)
        writer.writeBits(0x5AA5, count: 16)
        writer.flush()
        return writer.data
    }

    private func compare(_ bytes: [UInt8], columns: Int, rows: Int,
                         interval: Int, offset: Int, precision: Int,
                         dcTable: HuffmanTable? = nil, acTable: HuffmanTable? = nil) throws -> Bool {
        let dc = dcTable ?? self.dc, ac = acTable ?? self.ac
        var expected = BitReader(data: bytes), actual = expected
        if offset > 0 {
            _ = try expected.readBits(offset)
            _ = try actual.readBits(offset)
        }
        var expectedValues: [Int32] = [], actualValues: [Int32] = []
        var expectedStarts: [Int] = [], actualStarts: [Int] = []
        let reference = Result {
            try SequentialGreyscaleDecoder.decodeBatches(reader: &expected, dcTable: dc, acTable: ac,
                lookup: nil, blocksPerRow: columns, blockRows: rows, precision: precision,
                restartInterval: interval) { values, first in
                #expect(values.enumerated().allSatisfy { $0.offset % 64 == 0 || $0.element == 0 })
                expectedValues += stride(from: 0, to: values.count, by: 64).map { values[$0] }
                expectedStarts.append(first)
            }
        }
        let candidate = Result {
            try DCOnlyGreyscaleDecoder.decodeBatches(reader: &actual, dcTable: dc, acTable: ac,
                blocksPerRow: columns, blockRows: rows, precision: precision,
                restartInterval: interval) { values, first in
                actualValues.append(contentsOf: values)
                actualStarts.append(first)
                values.baseAddress!.update(repeating: 123456, count: values.count)
            }
        }
        #expect(actualValues == expectedValues && actualStarts == expectedStarts)
        #expect(actual.byteOffset == expected.byteOffset)
        switch (reference, candidate) {
        case (.success, .success):
            let left = Result {
                try expected.skipRestartMarker(expectedIndex: 3)
                return try expected.readBits(16)
            }
            let right = Result {
                try actual.skipRestartMarker(expectedIndex: 3)
                return try actual.readBits(16)
            }
            #expect(actual.byteOffset == expected.byteOffset)
            switch (left, right) {
            case (.success(let a), .success(let b)):
                #expect(a == 0x5AA5 && b == a)
                return true
            case (.failure(let a), .failure(let b)):
                #expect(String(describing: a) == String(describing: b))
                return false
            default:
                Issue.record("Zero-pair run changed the trailing marker or sample")
                return false
            }
        case (.failure(let left), .failure(let right)):
            #expect(String(describing: left) == String(describing: right))
            // Compare the remaining logical bits as well as the physical
            // cursor. Errors may stop between a DC symbol and its EOB.
            for _ in 0..<16 {
                let a = Result { try expected.readBit() }, b = Result { try actual.readBit() }
                #expect(String(describing: a) == String(describing: b))
                #expect(actual.byteOffset == expected.byteOffset)
            }
            return false
        default:
            Issue.record("Zero-pair run changed entropy success or failure")
            return false
        }
    }

    @Test func rowsRestartsBatchesAndNonzeroPrefixesMatchScalar() throws {
        for precision in [8, 12] {
            for interval in [0, 1, 17, 31, 1023, 1024, 1025] {
                for offset in 0..<8 {
                    #expect(try compare(entropy(blocks: 1030, interval: interval, offset: offset),
                        columns: 103, rows: 10, interval: interval, offset: offset, precision: precision))
                }
            }
        }
    }

    @Test func oneBitCodeMustMeanZeroDCAndEOB() throws {
        for firstDC: UInt8 in [0, 1] { for firstAC: UInt8 in [0, 0xF0] {
            let dc = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14),
                values: firstDC == 0 ? [0, 1] : [1, 0])
            let ac = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14),
                values: firstAC == 0 ? [0, 0xF0] : [0xF0, 0])
            var writer = BitWriter()
            for _ in 0..<19 {
                // Category1's negative magnitude adds a zero bit. A decoder
                // checking code length without its symbol would misread this.
                HuffmanEncoder.encodeDC(firstDC == 0 ? 0 : -1, table: dc, writer: &writer)
                let code = ac.encodingTable[Int(firstAC)]
                for _ in 0..<(firstAC == 0 ? 1 : 4) {
                    writer.writeBits(UInt32(code.code), count: Int(code.length))
                }
            }
            writer.emitRestartMarker(3)
            writer.writeBits(0x5AA5, count: 16)
            writer.flush()
            #expect(try compare(writer.data, columns: 19, rows: 1,
                interval: 0, offset: 0, precision: 8, dcTable: dc, acTable: ac))
        } }
    }

    @Test func truncationsAndMarkersPreserveErrorAndPublishedPrefix() throws {
        for interval in [0, 17, 1024] {
            let complete = entropy(blocks: 1030, interval: interval, offset: 0)
            var ends = Set([0, 1, 2, 3, 7, 8, 9])
            for end in max(0, complete.count - 12)..<complete.count { ends.insert(end) }
            for index in 0..<(complete.count - 1) where complete[index] == 0xFF {
                for end in max(0, index - 1)...min(complete.count, index + 2) { ends.insert(end) }
            }
            for end in ends.sorted() {
                _ = try compare(Array(complete.prefix(end)), columns: 103, rows: 10,
                    interval: interval, offset: 0, precision: 12)
            }
        }
    }

    @Test func rawPairsRetainBufferedRemainderAndBoundedShifts() throws {
        let zero = HuffmanTable(bits: [1] + Array(repeating: 0, count: 15), values: [0])
        let bytes = Array(repeating: UInt8(0), count: 32) + [0x5A, 0xFF, 0, 0xA5]
        for skip in 0...64 { for maximum in [0, -1, 1, 2, 3, 7, 28, 29, Int.max] {
            var actual = BitReader(data: bytes), expected = actual
            for _ in 0..<skip { _ = try actual.readBit(); _ = try expected.readBit() }
            let run = actual.consumeZeroCodePairs(maximum: maximum)
            #expect(run >= 0 && run <= 28)
            if maximum <= 0 { #expect(run == 0) }
            for _ in 0..<run {
                #expect(try HuffmanDecoder.decodeSymbol(from: &expected, table: zero) == 0)
                #expect(try HuffmanDecoder.decodeSymbol(from: &expected, table: zero) == 0)
            }
            // Reading the remainder also closes any harmless initial fill
            // when the pair helper returned zero without consuming a symbol.
            for _ in 0..<72 {
                #expect(try actual.readBit() == expected.readBit())
                #expect(actual.byteOffset == expected.byteOffset)
            }
        } }
    }
}
