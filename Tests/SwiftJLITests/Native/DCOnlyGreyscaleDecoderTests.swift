// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct DCOnlyGreyscaleDecoderTests {
    private func table(codeLength: Int) -> HuffmanTable {
        var bits = [UInt8](repeating: 0, count: 16)
        bits[codeLength - 1] = 16
        return HuffmanTable(bits: bits, values: (0..<16).map { UInt8($0 << 4) })
    }

    private func entropy(blocks: Int, interval: Int, ac: HuffmanTable) -> [UInt8] {
        var writer = BitWriter(), previous: Int32 = 0
        for index in 0..<blocks {
            if interval > 0, index > 0, index % interval == 0 {
                writer.emitRestartMarker((index / interval - 1) & 7)
                previous = 0
            }
            let dc = Int32(index % 511 - 255)
            HuffmanEncoder.encodeDC(dc - previous, table: StandardHuffmanTables.dcLuminance, writer: &writer)
            previous = dc
            // Every zero-category symbol, including non-standard run/zero and
            // overshooting runs, follows the retained decoder's exact semantics.
            let symbol = UInt8((index % 16) << 4)
            let entry = ac.encodingTable[Int(symbol)]
            var coefficient = 1
            while coefficient < 64 {
                writer.writeBits(UInt32(entry.code), count: Int(entry.length))
                if symbol == 0 { break }
                if symbol == 0xF0 { coefficient += 16 }
                else { coefficient += Int(symbol >> 4) + 1 }
            }
        }
        writer.emitRestartMarker(3)
        writer.writeBits(0x5A, count: 8)
        writer.flush()
        return writer.data
    }

    @Test(arguments: [8, 12])
    func compactValuesAndCursorMatchFullCoefficientsAcrossRunsRestartsAndTails(precision: Int) throws {
        for codeLength in [5, 9, 16] { for interval in [0, 1, 1023, 1024, 1025] {
            let ac = table(codeLength: codeLength)
            #expect(DCOnlyGreyscaleDecoder.accepts(ac))
            #expect(ACLookahead(table: ac, blockCount: 2050) == nil)
            let bytes = entropy(blocks: 2050, interval: interval, ac: ac)
            var reference = BitReader(data: bytes), actual = reference
            var expected: [Int32] = [], decoded: [Int32] = [], starts: [Int] = []
            try SequentialGreyscaleDecoder.decodeBatches(reader: &reference,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: ac, lookup: nil,
                blocksPerRow: 41, blockRows: 50, precision: precision, restartInterval: interval) { block, _ in
                #expect(block.enumerated().allSatisfy { $0.offset % 64 == 0 || $0.element == 0 })
                expected += stride(from: 0, to: block.count, by: 64).map { block[$0] }
            }
            try DCOnlyGreyscaleDecoder.decodeBatches(reader: &actual,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: ac,
                blocksPerRow: 41, blockRows: 50, precision: precision, restartInterval: interval) { dc, first in
                #expect(dc.count <= 1024)
                starts.append(first); decoded.append(contentsOf: dc)
                dc.baseAddress!.update(repeating: 123456, count: dc.count)
            }
            #expect(decoded == expected)
            #expect(starts == [0, 1024, 2048])
            #expect(reference.byteOffset == actual.byteOffset)
            try reference.skipRestartMarker(expectedIndex: 3)
            try actual.skipRestartMarker(expectedIndex: 3)
            #expect(try reference.readBits(8) == 0x5A)
            #expect(try actual.readBits(8) == 0x5A)
        } }
    }

    @Test func malformedEntropyAndConsumerFailureKeepBatchBoundary() throws {
        let ac = table(codeLength: 5)
        let complete = entropy(blocks: 2050, interval: 1024, ac: ac)
        let marker = try #require((0..<(complete.count - 1)).first { complete[$0] == 0xFF && complete[$0 + 1] == 0xD0 })
        var wrongRestart = complete
        wrongRestart[marker + 1] = 0xD3
        // The retained reader accepts any RST0...RST7 order. Preserve that
        // behaviour; truncation still fails and no partial batch is published.
        for (bytes, shouldFail) in [(Array(complete.prefix(marker + 15)), true),
                                    (wrongRestart, false), ([UInt8](), true)] {
            var reference = BitReader(data: bytes), actual = reference
            var referenceCalls: [Int] = [], actualCalls: [Int] = []
            let referenceError = Result { try SequentialGreyscaleDecoder.decodeBatches(reader: &reference,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: ac, lookup: nil,
                blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 1024) { _, first in
                referenceCalls.append(first)
            } }
            let actualError = Result { try DCOnlyGreyscaleDecoder.decodeBatches(reader: &actual,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: ac,
                blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 1024) { _, first in
                actualCalls.append(first)
            } }
            switch (referenceError, actualError) {
            case (.failure(let expected), .failure(let received)) where shouldFail:
                #expect(String(describing: expected) == String(describing: received))
            case (.success, .success) where !shouldFail: break
            default: Issue.record("Compact scan diverged from retained restart/error semantics")
            }
            #expect(actualCalls == referenceCalls)
            reference.alignToByte(); actual.alignToByte()
            #expect(actual.byteOffset == reference.byteOffset)
        }
        var reader = BitReader(data: complete), calls = 0
        #expect(throws: CancellationError.self) {
            try DCOnlyGreyscaleDecoder.decodeBatches(reader: &reader,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: ac,
                blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 1024) { values, first in
                calls += 1
                #expect(first == 0 && values.count == 1024)
                values.baseAddress!.update(repeating: 123456, count: values.count)
                throw CancellationError()
            }
        }
        #expect(calls == 1)
        try reader.skipRestartMarker(expectedIndex: 0)
    }

    @Test func outOfRangeDCAndExpiredOperationPublishNothing() throws {
        let ac = table(codeLength: 5)
        var writer = BitWriter()
        HuffmanEncoder.encodeDC(1025, table: StandardHuffmanTables.dcLuminance, writer: &writer)
        writer.writeBits(0, count: 5)
        writer.flush()
        for expired in [false, true] {
            var reader = BitReader(data: writer.data)
            let result = Result {
                try NativeOperation.$current.withValue(.init(seconds: expired ? Double.leastNonzeroMagnitude : 120)) {
                    try DCOnlyGreyscaleDecoder.decodeBatches(reader: &reader,
                        dcTable: StandardHuffmanTables.dcLuminance, acTable: ac,
                        blocksPerRow: 1, blockRows: 1, precision: 8, restartInterval: 0) { _, _ in
                        Issue.record("Invalid or cancelled compact scan published output")
                    }
                }
            }
            switch result {
            case .failure(let error): #expect(expired ? error is CodecError : error is JLIError)
            case .success: Issue.record("Invalid or cancelled compact scan succeeded")
            }
        }
    }

    @Test func invalidTablesAndGeometryRejectBeforeConsumption() throws {
        #expect(!DCOnlyGreyscaleDecoder.accepts(StandardHuffmanTables.acLuminance))
        var mixedReader = BitReader(data: [0])
        #expect(throws: JLIError.self) {
            try DCOnlyGreyscaleDecoder.decodeBatches(reader: &mixedReader,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: StandardHuffmanTables.acLuminance,
                blocksPerRow: 1, blockRows: 1, precision: 8, restartInterval: 0) { _, _ in
                Issue.record("Mixed AC table was accepted by the compact decoder")
            }
        }
        #expect(mixedReader.byteOffset == 0)
        #expect(!DCOnlyGreyscaleDecoder.accepts(HuffmanTable(bits: [UInt8](repeating: 0, count: 16), values: [])))
        for (columns, rows, precision, interval) in [(0, 1, 8, 0), (1, 0, 8, 0),
            (Int.max, 2, 8, 0), (Int.max / 32, 1, 8, 0), (1, 1, 7, 0), (1, 1, 13, 0), (1, 1, 8, -1)] {
            var reader = BitReader(data: [0])
            #expect(throws: JLIError.self) {
                try DCOnlyGreyscaleDecoder.decodeBatches(reader: &reader,
                    dcTable: StandardHuffmanTables.dcLuminance, acTable: table(codeLength: 5),
                    blocksPerRow: columns, blockRows: rows, precision: precision, restartInterval: interval) { _, _ in
                    Issue.record("Invalid compact scan published coefficients")
                }
            }
            #expect(reader.byteOffset == 0)
        }
    }
}
