// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Suite struct StreamingCoefficientReuseTests {
    private static func scan(blockCount: Int, dcOnly: Bool = false) -> (bytes: [UInt8], coefficients: [Int32]) {
        var writer = BitWriter(), previous: Int32 = 0
        var coefficients: [Int32] = []
        for index in 0..<blockCount {
            var block = [Int32](repeating: 0, count: 64)
            block[0] = Int32(index % 511 - 255)
            if !dcOnly, index % 3 != 0 {
                for k in stride(from: 1 + index % 13, to: 64, by: 17) {
                    block[k] = Int32((index + k) % 63 - 31)
                }
            }
            HuffmanEncoder.encodeDC(block[0] - previous, table: StandardHuffmanTables.dcLuminance,
                writer: &writer)
            HuffmanEncoder.encodeAC(block, table: StandardHuffmanTables.acLuminance, writer: &writer)
            previous = block[0]
            coefficients += block
        }
        writer.flush()
        return (writer.data, coefficients)
    }

    @Test(arguments: [false, true], [false, true])
    func reusedCoefficientsMatchSeparateOutputIncludingTail(combined: Bool, dcOnly: Bool) throws {
        let scan = Self.scan(blockCount: 2050, dcOnly: dcOnly)
        let table = StandardHuffmanTables.acLuminance
        let lookup = combined ? try #require(ACLookahead(table: table, blockCount: 2050)) : nil
        let quantisation = (0..<64).map { Float($0 * 7 % 127 + 1) }
        for backend in Decoder.capabilities.availableBackends {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                var reader = BitReader(data: scan.bytes), consumed = 0
                var expected = [Float](repeating: .nan, count: 1024 * 64)
                var scratch = expected
                try quantisation.withUnsafeBufferPointer { qt in
                    try expected.withUnsafeMutableBufferPointer { reference in
                        try scratch.withUnsafeMutableBufferPointer { workspace in
                            try scan.coefficients.withUnsafeBufferPointer { original in
                                try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                                    dcTable: StandardHuffmanTables.dcLuminance, acTable: table, lookup: lookup,
                                    blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 0) { coefficients, first in
                                    let count = coefficients.count, blocks = count / 64
                                    #expect(first == consumed)
                                    #expect(coefficients.elementsEqual(
                                        original[(first * 64)..<(first * 64 + count)]))
                                    AccelerateDSP.inverseDCTBatchDequantized(
                                        zigzag: original.baseAddress! + first * 64, quantTable: qt.baseAddress!,
                                        output: reference.baseAddress!, scratch: workspace.baseAddress!, blockCount: blocks)
                                    let preparedDC = AccelerateDSP.prepareDCOnlyDCTBatch(
                                        zigzag: UnsafePointer(coefficients.baseAddress!), quantTable: qt.baseAddress!,
                                        scratch: workspace.baseAddress!, blockCount: blocks)
                                    #expect(preparedDC == dcOnly)
                                    if !preparedDC {
                                        AccelerateDSP.packDequantizedDCTBatch(
                                            zigzag: UnsafePointer(coefficients.baseAddress!), quantTable: qt.baseAddress!,
                                            scratch: workspace.baseAddress!, blockCount: blocks)
                                    }
                                    coefficients.baseAddress!.withMemoryRebound(to: Float.self, capacity: count) { pixels in
                                        if preparedDC {
                                            AccelerateDSP.writeDCOnlyDCTBatch(values: UnsafePointer(workspace.baseAddress!),
                                                output: pixels, blockCount: blocks)
                                        } else {
                                            AccelerateDSP.inverseDCTBatchPacked(output: pixels,
                                                scratch: workspace.baseAddress!, blockCount: blocks)
                                        }
                                        let actual = UnsafeBufferPointer(start: pixels, count: count)
                                        #expect(zip(actual, reference.prefix(count)).allSatisfy {
                                            $0.bitPattern == $1.bitPattern
                                        })
                                        // Poison every consumed slot. The next entropy batch
                                        // must fully reset it, including all zero AC coefficients.
                                        pixels.update(repeating: .nan, count: count)
                                    }
                                    consumed += blocks
                                }
                            }
                        }
                    }
                }
                #expect(consumed == 2050)
            }
        }
    }

    @Test(arguments: [false, true])
    func malformedLaterBatchIsNeverConsumedAfterRebinding(combined: Bool) throws {
        let scan = Self.scan(blockCount: 1025)
        let table = StandardHuffmanTables.acLuminance
        let lookup = combined ? try #require(ACLookahead(table: table, blockCount: 2050)) : nil
        var reader = BitReader(data: scan.bytes), calls = 0
        #expect(throws: JLIError.self) {
            try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                dcTable: StandardHuffmanTables.dcLuminance, acTable: table, lookup: lookup,
                blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 0) { coefficients, first in
                #expect(first == 0 && coefficients.count == 1024 * 64)
                calls += 1
                let count = coefficients.count
                coefficients.baseAddress!.withMemoryRebound(to: Float.self, capacity: count) {
                    $0.update(repeating: .nan, count: count)
                }
            }
        }
        #expect(calls == 1)
    }
}
