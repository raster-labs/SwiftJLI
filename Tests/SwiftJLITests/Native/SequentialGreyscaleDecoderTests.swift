// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct SequentialGreyscaleDecoderTests {
    @Test func invalidWindowExtentsRejectBeforeReadingEntropy() throws {
        for (group, windows) in [(1024, [-1, 0, 1023, 1025, 8193, Int.max]),
                                 (256, [-1, 0, 255, 257, 8193, Int.max])] {
            for window in windows {
                var reader = BitReader(data: []), calls = 0
                #expect(throws: JLIError.self) {
                    try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                        dcTable: StandardHuffmanTables.dcLuminance, acTable: StandardHuffmanTables.acLuminance,
                        lookup: nil, blocksPerRow: 4100, blockRows: 2, precision: 12, restartInterval: 0,
                        windowBlocks: window, transformGroupBlocks: group) { _, _ in calls += 1 }
                }
                #expect(calls == 0 && reader.byteOffset == 0)
            }
        }
    }

    @Test func invalidTransformGroupsRejectBeforeModulo() throws {
        for group in [Int.min, -1, 0, 1, 255, 257, 1023, 1025, Int.max] {
            var reader = BitReader(data: []), calls = 0
            #expect(throws: JLIError.self) {
                try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                    dcTable: StandardHuffmanTables.dcLuminance, acTable: StandardHuffmanTables.acLuminance,
                    lookup: nil, blocksPerRow: 4100, blockRows: 2, precision: 12, restartInterval: 0,
                    windowBlocks: 256, transformGroupBlocks: group) { _, _ in calls += 1 }
            }
            #expect(calls == 0 && reader.byteOffset == 0)
        }
    }

    @Test(arguments: [256, 2048, 8192])
    func groupedWindowsPreserveRestartPredictionAndFullyResetSlots(window: Int) throws {
        let dcTable = StandardHuffmanTables.dcLuminance, acTable = StandardHuffmanTables.acLuminance
        let group = window == 256 ? 256 : 1024
        let intervals = window == 256 ? [255, 256, 257, 1023, 2048, 8193] : [1023, 2048, 8193]
        for interval in intervals {
            var writer = BitWriter(), previous: Int32 = 0
            var expected: [Int32] = []
            for index in 0..<8200 {
                if index > 0 && index % interval == 0 {
                    writer.emitRestartMarker((index / interval - 1) & 7); previous = 0
                }
                var block = [Int32](repeating: 0, count: 64)
                block[0] = Int32(index % 511 - 255)
                if index % 3 == 0 { block[63] = 7 }
                HuffmanEncoder.encodeDC(block[0] - previous, table: dcTable, writer: &writer)
                HuffmanEncoder.encodeAC(block, table: acTable, writer: &writer)
                previous = block[0]; expected += block
            }
            writer.flush()
            var reader = BitReader(data: writer.data), received = 0
            let lookup = try #require(ACLookahead(table: acTable, blockCount: 8200))
            try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                dcTable: dcTable, acTable: acTable, lookup: lookup,
                blocksPerRow: 4100, blockRows: 2, precision: 12, restartInterval: interval,
                windowBlocks: window, transformGroupBlocks: group) { coefficients, first in
                #expect(first == received / 64 && first % group == 0)
                #expect(coefficients.elementsEqual(expected[received..<(received + coefficients.count)]))
                received += coefficients.count
                coefficients.baseAddress!.update(repeating: 123456, count: coefficients.count)
            }
            #expect(received == expected.count)
        }
    }

    @Test(arguments: [8, 12])
    func scanBorrowMatchesReferenceAcrossRestartsAndLookup(precision: Int) throws {
        let dcTable = StandardHuffmanTables.dcLuminance
        let acTable = StandardHuffmanTables.acLuminance
        for dimensions in [(1, 1), (3, 5), (32, 17), (65, 49)] {
            let (columns, rows) = dimensions
            for interval in [0, 1, 7, 32, 1023, 1024, 1025] {
                var writer = BitWriter()
                var previous: Int32 = 0
                var expected: [Int32] = []
                for index in 0..<(columns * rows) {
                    if interval > 0, index > 0, index % interval == 0 {
                        writer.emitRestartMarker((index / interval - 1) & 7)
                        previous = 0
                    }
                    var block = [Int32](repeating: 0, count: 64)
                    block[0] = Int32(index % 511 - 255)
                    for k in stride(from: 1 + index % 13, to: 64, by: 17) {
                        block[k] = Int32((index + k) % 127 - 63)
                    }
                    HuffmanEncoder.encodeDC(block[0] - previous, table: dcTable, writer: &writer)
                    HuffmanEncoder.encodeAC(block, table: acTable, writer: &writer)
                    previous = block[0]
                    expected += block
                }
                writer.emitRestartMarker(3)
                writer.writeBits(0x5A, count: 8)
                writer.flush()
                for combined in [false, true] {
                    var reader = BitReader(data: writer.data)
                    var destination = [Int32](repeating: 123456, count: expected.count + 7)
                    let lookup = combined ? try #require(ACLookahead(table: acTable, blockCount: 512)) : nil
                    try destination.withUnsafeMutableBufferPointer {
                        try SequentialGreyscaleDecoder.decode(reader: &reader,
                            dcTable: dcTable, acTable: acTable, lookup: lookup,
                            coefficients: .init(rebasing: $0[3..<(3 + expected.count)]),
                            blocksPerRow: columns, blockRows: rows,
                            precision: precision, restartInterval: interval)
                    }
                    #expect(destination[3..<(3 + expected.count)].elementsEqual(expected))
                    #expect(destination.prefix(3).allSatisfy { $0 == 123456 })
                    #expect(destination.suffix(4).allSatisfy { $0 == 123456 })
                    try reader.skipRestartMarker(expectedIndex: 3)
                    #expect(try reader.readBits(8) == 0x5A)

                    var batchReader = BitReader(data: writer.data)
                    var collected: [Int32] = []
                    try SequentialGreyscaleDecoder.decodeBatches(reader: &batchReader,
                        dcTable: dcTable, acTable: acTable, lookup: lookup,
                        blocksPerRow: columns, blockRows: rows,
                        precision: precision, restartInterval: interval) { block, first in
                        #expect(first == collected.count / 64)
                        #expect(block.count <= 1024 * 64)
                        collected.append(contentsOf: block)
                    }
                    #expect(collected == expected)
                    try batchReader.skipRestartMarker(expectedIndex: 3)
                    #expect(try batchReader.readBits(8) == 0x5A)
                }
            }
        }
    }

    @Test func batchConsumerFailureStopsBeforeReusingItsBorrow() throws {
        var writer = BitWriter()
        let dcTable = StandardHuffmanTables.dcLuminance
        let acTable = StandardHuffmanTables.acLuminance
        let block = [Int32](repeating: 0, count: 64)
        for _ in 0..<2050 {
            HuffmanEncoder.encodeDC(0, table: dcTable, writer: &writer)
            HuffmanEncoder.encodeAC(block, table: acTable, writer: &writer)
        }
        writer.flush()
        var reader = BitReader(data: writer.data)
        var calls = 0
        #expect(throws: CancellationError.self) {
            try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                dcTable: dcTable, acTable: acTable, lookup: nil,
                blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 0) { coefficients, first in
                calls += 1
                #expect(first == 0 && coefficients.count == 1024 * 64)
                #expect(coefficients.allSatisfy { $0 == 0 })
                // Throw from the temporary Float binding, then access Int32
                // again only after withMemoryRebound has restored its binding.
                let count = coefficients.count
                do {
                    try coefficients.baseAddress!.withMemoryRebound(to: Float.self,
                        capacity: count) { pixels in
                        pixels.update(repeating: .nan, count: count)
                        throw CancellationError()
                    }
                } catch {
                    #expect(coefficients[0] == Int32(bitPattern: Float.nan.bitPattern))
                    throw error
                }
            }
        }
        #expect(calls == 1)
        // The failure does not leave a worker or borrowed owner alive. A new
        // invocation can immediately consume all batches with independent state.
        reader = BitReader(data: writer.data)
        var received = 0
        try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
            dcTable: dcTable, acTable: acTable, lookup: nil,
            blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 0) { coefficients, _ in
            received += coefficients.count / 64
        }
        #expect(received == 2050)
    }

    @Test func invalidExtentsRejectBeforeWriting() throws {
        let table = StandardHuffmanTables.dcLuminance
        for (columns, rows, precision, interval) in [
            (0, 1, 8, 0), (1, 0, 8, 0), (-1, 1, 8, 0),
            (Int.max, 2, 8, 0), (Int.max / 32, 1, 8, 0),
            (2, 1, 8, 0), (1, 1, 7, 0), (1, 1, 13, 0), (1, 1, 8, -1)
        ] {
            var destination = [Int32](repeating: 123456, count: 64)
            var reader = BitReader(data: [])
            #expect(throws: JLIError.self) {
                try destination.withUnsafeMutableBufferPointer {
                    try SequentialGreyscaleDecoder.decode(reader: &reader,
                        dcTable: table, acTable: StandardHuffmanTables.acLuminance,
                        lookup: nil, coefficients: $0, blocksPerRow: columns,
                        blockRows: rows, precision: precision, restartInterval: interval)
                }
            }
            #expect(destination.allSatisfy { $0 == 123456 })
            #expect(reader.byteOffset == 0)
        }
    }

    @Test func malformedEntropyAndExpiredOperationsStillReject() throws {
        for expired in [false, true] {
            var destination = [Int32](repeating: 123456, count: 64)
            var reader = BitReader(data: [])
            let outcome = Result {
                try NativeOperation.$current.withValue(.init(seconds: expired ? Double.leastNonzeroMagnitude : 5)) {
                    try destination.withUnsafeMutableBufferPointer {
                        try SequentialGreyscaleDecoder.decode(reader: &reader,
                            dcTable: StandardHuffmanTables.dcLuminance,
                            acTable: StandardHuffmanTables.acLuminance,
                            lookup: nil, coefficients: $0, blocksPerRow: 1,
                            blockRows: 1, precision: 8, restartInterval: 0)
                    }
                }
            }
            switch outcome {
            case .success: Issue.record("Invalid scan unexpectedly accepted")
            case .failure(let error):
                #expect(expired ? error is CodecError : error is JLIError)
            }
            #expect(destination.allSatisfy { $0 == 123456 })
        }
    }
}
