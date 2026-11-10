// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct CSequentialGreyscaleTests {
    @Test(arguments: [256, 1024])
    func ineligibleRouteDoesNotConsumeOrPublish(group: Int) throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 2048))
        // Safe internal construction that the C metadata guard must reject.
        // Public parsing rejects this oversized value list before decoding.
        let oversized = HuffmanTable(bits: Array(repeating: 0, count: 16),
            values: Array(repeating: 0, count: 257))
        let cases: [(Backend, Int, HuffmanTable, HuffmanTable, ACLookahead?)] = [
            (.scalarCPU, 8, dc, ac, lookup),
            (.accelerated, 9, dc, ac, lookup),
            (.accelerated, 10, dc, ac, lookup),
            (.accelerated, 11, dc, ac, lookup),
            (.accelerated, 8, dc, ac, nil),
            (.accelerated, 8, oversized, ac, lookup),
            (.accelerated, 8, dc, oversized, lookup)
        ]
        let bytes: [UInt8] = [0xAB, 0xCD, 0x12, 0x34, 0x56, 0x78, 0x90, 0x42,
            0xFF, 0, 0x55, 0xFF, 0xD9]
        for (backend, precision, dcTable, acTable, tableLookup) in cases {
            for skip in [0, 3, 7] {
                var reference = BitReader(data: bytes)
                _ = try reference.readBits(skip)
                var candidate = reference, publications = 0
                let handled = try NativeOperation.$current.withValue(
                    .init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                    try CSequentialGreyscaleDecoder.decodeBatchesIfEligible(
                        reader: &candidate, dcTable: dcTable, acTable: acTable,
                        lookup: tableLookup, blocksPerRow: 64, blockRows: 32,
                        precision: precision, restartInterval: 0,
                        windowBlocks: group, transformGroupBlocks: group) { _, _ in
                            publications += 1
                        }
                }
                #expect(!handled && publications == 0)
                #expect(candidate.byteOffset == reference.byteOffset)
                var alignedReference = reference, alignedCandidate = candidate
                alignedReference.alignToByte(); alignedCandidate.alignToByte()
                #expect(alignedCandidate.byteOffset == alignedReference.byteOffset)
                // Observe the buffered suffix too, including stuffing/marker
                // errors; equal physical cursors alone would miss consumption.
                for _ in 0..<20 {
                    let lhs = Result { try reference.readBits(8) }
                    let rhs = Result { try candidate.readBits(8) }
                    switch (lhs, rhs) {
                    case (.success(let a), .success(let b)): #expect(a == b)
                    case (.failure(let a), .failure(let b)):
                        #expect(String(describing: a) == String(describing: b))
                    default: Issue.record("Declined C route changed entropy state")
                    }
                    #expect(candidate.byteOffset == reference.byteOffset)
                }
            }
        }
    }

    @Test(arguments: [8, 9, 12])
    func borrowedKernelPreservesBatchesRestartsAndReusedStorage(precision: Int) throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let width = 65, rows = 33, count = width * rows
        let lookup = try #require(ACLookahead(table: ac, blockCount: count))
        let configurations = [(1024, 1024, 0), (2048, 1024, 1023), (1024, 1024, 1024),
                              (256, 256, 255), (256, 256, 256), (256, 256, 257),
                              (1024, 256, 1023)]
        for (window, group, restart) in configurations {
            var writer = BitWriter(), previous: Int32 = 0
            var expected: [[Int32]] = []
            for index in 0..<count {
                if restart > 0, index > 0, index % restart == 0 {
                    writer.emitRestartMarker((index / restart - 1) & 7)
                    previous = 0
                }
                var block = [Int32](repeating: 0, count: 64)
                block[0] = Int32(index % 127 - 63)
                block[1 + index % 63] = Int32(index % 31 - 15)
                HuffmanEncoder.encodeDC(block[0] - previous, table: dc, writer: &writer)
                HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
                previous = block[0]
                expected.append(block)
            }
            writer.flush()
            for backend in [Backend.scalarCPU, .accelerated] {
                var reader = BitReader(data: writer.data), consumed = 0
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                    try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                        dcTable: dc, acTable: ac, lookup: lookup,
                        blocksPerRow: width, blockRows: rows, precision: precision,
                        restartInterval: restart, windowBlocks: window,
                        transformGroupBlocks: group) { buffer, first in
                        #expect(first == consumed)
                        #expect(buffer.count == min(window, count - first) * 64)
                        for block in 0..<(buffer.count / 64) {
                            #expect(buffer[(block * 64)..<((block + 1) * 64)]
                                .elementsEqual(expected[first + block]))
                        }
                        consumed += buffer.count / 64
                        // The real consumer overwrites each consumed slot.
                        // No previous coefficient may survive the next batch.
                        buffer.update(repeating: 919)
                    }
                }
                #expect(consumed == count)
            }
        }
    }

    @Test(.enabled(if: SwiftJLI.Decoder.capabilities.availableBackends.contains(.accelerated)),
        arguments: [8, 12])
    func eligibleHelperPublishesExactCoefficientsAndPartialFinalWindow(precision: Int) throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let width = 17, rows = 31, count = width * rows
        let lookup = try #require(ACLookahead(table: ac, blockCount: count))
        // The 256 case ends in a 15-block partial window. A 1023-block window
        // is legal for a smaller whole scan even though it is not group-aligned.
        for (window, group, restart) in [(256, 256, 257), (1023, 1024, 0), (1024, 1024, 0)] {
            var writer = BitWriter(), previous: Int32 = 0
            var expected: [[Int32]] = []
            for index in 0..<count {
                if restart > 0, index > 0, index % restart == 0 {
                    writer.emitRestartMarker((index / restart - 1) & 7)
                    previous = 0
                }
                var block = [Int32](repeating: 0, count: 64)
                block[0] = Int32(index % 127 - 63)
                block[1 + index % 63] = Int32(index % 31 - 15)
                HuffmanEncoder.encodeDC(block[0] - previous, table: dc, writer: &writer)
                HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
                previous = block[0]
                expected.append(block)
            }
            writer.flush()
            var reader = BitReader(data: writer.data), firsts: [Int] = []
            let handled = try NativeOperation.$current.withValue(
                .init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
                try CSequentialGreyscaleDecoder.decodeBatchesIfEligible(reader: &reader,
                    dcTable: dc, acTable: ac, lookup: lookup, blocksPerRow: width,
                    blockRows: rows, precision: precision, restartInterval: restart,
                    windowBlocks: window, transformGroupBlocks: group) { coefficients, first in
                    firsts.append(first)
                    #expect(coefficients.count == min(window, count - first) * 64)
                    for block in 0..<(coefficients.count / 64) {
                        #expect(coefficients[(block * 64)..<((block + 1) * 64)]
                            .elementsEqual(expected[first + block]))
                    }
                    coefficients.update(repeating: 919)
                }
            }
            // A comparison through the public dispatcher alone could pass
            // while silently staying on Swift; require direct C admission.
            #expect(handled)
            #expect(firsts == Array(stride(from: 0, to: count, by: window)))
        }
    }

    @Test(.enabled(if: SwiftJLI.Decoder.capabilities.availableBackends.contains(.accelerated)))
    func eligibleHelperRejectsInvalidGroupsAndExtentsBeforeEntropyOrPublication() throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 2048))
        try CDCTKernel.withBorrowed(dcTable: dc, acTable: ac, lookup: lookup, enabled: true) { kernel in
            _ = try #require(kernel)
        }
        let invalid: [(width: Int, rows: Int, window: Int, group: Int, restart: Int)] = [
            (64, 32, 1024, 0, 0), (64, 32, 1024, 255, 0),
            (64, 32, 1024, 257, 0), (64, 32, 1024, 2048, 0),
            (64, 32, 0, 256, 0), (64, 32, 255, 256, 0),
            (64, 32, 1023, 1024, 0),
            (64, 32, SequentialGreyscalePlan.maximumWindowBlocks + 1, 256, 0),
            (0, 32, 256, 256, 0), (64, -1, 256, 256, 0),
            (Int.max, 2, 256, 256, 0), (Int.max / 64 + 1, 1, 256, 256, 0),
            (64, 32, 256, 256, -1)
        ]
        for item in invalid {
            var reference = BitReader(data: [0xAB, 0xCD, 0x12, 0x34, 0xFF, 0, 0x55, 0xFF, 0xD9])
            _ = try reference.readBits(3)
            var reader = reference, publications = 0
            #expect(throws: JLIError.self) {
                try NativeOperation.$current.withValue(
                    .init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
                    _ = try CSequentialGreyscaleDecoder.decodeBatchesIfEligible(reader: &reader,
                        dcTable: dc, acTable: ac, lookup: lookup, blocksPerRow: item.width,
                        blockRows: item.rows, precision: 8, restartInterval: item.restart,
                        windowBlocks: item.window, transformGroupBlocks: item.group) { _, _ in
                        publications += 1
                    }
                }
            }
            #expect(publications == 0 && reader.byteOffset == reference.byteOffset)
            for _ in 0..<12 {
                let lhs = Result { try reference.readBits(8) }
                let rhs = Result { try reader.readBits(8) }
                switch (lhs, rhs) {
                case (.success(let a), .success(let b)): #expect(a == b)
                case (.failure(let a), .failure(let b)):
                    #expect(String(describing: a) == String(describing: b))
                default: Issue.record("Rejected C geometry changed entropy state")
                }
                #expect(reader.byteOffset == reference.byteOffset)
            }
        }
    }

    @Test(arguments: [256, 1024])
    func truncatedFinalBatchIsNeverPublished(group: Int) throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 2048))
        var writer = BitWriter()
        let block = [Int32](repeating: 0, count: 64)
        // One complete window followed by a partially decoded window must
        // publish only the first; padding cannot supply another complete slot.
        for _ in 0..<(group + 3) {
            HuffmanEncoder.encodeDC(0, table: dc, writer: &writer)
            HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
        }
        writer.flush()
        var offsets: [Int] = []
        for backend in [Backend.scalarCPU, .accelerated] {
            var reader = BitReader(data: writer.data), publications = 0
            #expect(throws: JLIError.self) {
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                    try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                        dcTable: dc, acTable: ac, lookup: lookup,
                        blocksPerRow: 64, blockRows: 32, precision: 8, restartInterval: 0,
                        windowBlocks: group, transformGroupBlocks: group) { buffer, first in
                        #expect(first == 0)
                        #expect(buffer.count == group * 64)
                        publications += 1
                    }
                }
            }
            #expect(publications == 1)
            offsets.append(reader.byteOffset)
        }
        #expect(offsets[0] == offsets[1])
    }

    @Test(arguments: [256, 1024])
    func consumerFailurePropagatesWithoutStartingSwiftFallback(group: Int) throws {
        let dc = StandardHuffmanTables.dcLuminance, ac = StandardHuffmanTables.acLuminance
        let lookup = try #require(ACLookahead(table: ac, blockCount: 2050))
        let block = [Int32](repeating: 0, count: 64)
        var writer = BitWriter()
        for _ in 0..<2050 {
            HuffmanEncoder.encodeDC(0, table: dc, writer: &writer)
            HuffmanEncoder.encodeAC(block, table: ac, writer: &writer)
        }
        writer.flush()
        var offsets: [Int] = []
        for backend in [Backend.scalarCPU, .accelerated] {
            var reader = BitReader(data: writer.data), publications = 0
            #expect(throws: CancellationError.self) {
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                    try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                        dcTable: dc, acTable: ac, lookup: lookup,
                        blocksPerRow: 41, blockRows: 50, precision: 8, restartInterval: 0,
                        windowBlocks: group, transformGroupBlocks: group) { coefficients, first in
                        publications += 1
                        #expect(first == 0 && coefficients.count == group * 64)
                        #expect(coefficients.allSatisfy { $0 == 0 })
                        let base = try #require(coefficients.baseAddress)
                        let count = coefficients.count
                        do {
                            try base.withMemoryRebound(to: Float.self, capacity: count) { pixels in
                                pixels.update(repeating: .nan, count: count)
                                throw CancellationError()
                            }
                        } catch {
                            #expect(coefficients[0] == Int32(bitPattern: Float.nan.bitPattern))
                            throw error
                        }
                    }
                }
            }
            #expect(publications == 1)
            offsets.append(reader.byteOffset)
        }
        #expect(offsets[0] == offsets[1])
    }
}
