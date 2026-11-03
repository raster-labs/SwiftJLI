// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct SequentialGreyscaleDecoderTests {
    @Test(arguments: [8, 12])
    func scanBorrowMatchesReferenceAcrossRestartsAndLookup(precision: Int) throws {
        let dcTable = StandardHuffmanTables.dcLuminance
        let acTable = StandardHuffmanTables.acLuminance
        for dimensions in [(1, 1), (3, 5), (32, 17)] {
            let (columns, rows) = dimensions
            for interval in [0, 1, 7, 32] {
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
                }
            }
        }
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
