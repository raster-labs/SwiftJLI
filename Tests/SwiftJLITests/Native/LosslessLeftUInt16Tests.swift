// SPDX-License-Identifier: Apache-2.0
import Testing
import Synchronization
@testable import SwiftJLI

@Suite struct LosslessLeftUInt16Tests {
    /// Synthetic SOF3 scan with two length-two codes. Its categories cannot
    /// select either the zero-run or combined-lookup kernel. Category 16 uses
    /// the lossless no-magnitude-bit convention, including modulo wraparound.
    private func fixture(width: Int, height: Int, precision: Int = 16,
                         restartRows: Int = 0) throws -> (jpeg: [UInt8], expected: [UInt8], parsed: ParsedJPEG) {
        let lengths: [UInt8] = [0, 2] + Array(repeating: 0, count: 14)
        let table = HuffmanTable(bits: lengths, values: [1, 16])
        var entropy = BitWriter(), expected: [UInt8] = []
        let half = Int32(1 << (precision - 1))
        var previousRowFirst = half
        for y in 0..<height {
            let segmentStart = y == 0 || (restartRows > 0 && y % restartRows == 0)
            if y > 0 && segmentStart { entropy.emitRestartMarker((y / restartRows - 1) & 7) }
            var value = segmentStart ? half : previousRowFirst
            for x in 0..<width {
                let difference: Int32 = precision == 16 && (x + y) % 3 == 0
                    ? -32768 : ((x + y) % 2 == 0 ? 1 : -1)
                if difference == -32768 {
                    let code = table.encodingTable[16]
                    entropy.writeBits(UInt32(code.code), count: Int(code.length))
                } else {
                    HuffmanEncoder.encodeDC(difference, table: table, writer: &entropy)
                }
                value = (value + difference) & 0xFFFF
                if x == 0 { previousRowFirst = value }
                expected += [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]
            }
        }
        entropy.flush()
        var writer = MarkerWriter()
        writer.writeSOI()
        writer.writeSOF(progressive: false, precision: precision, width: width, height: height,
            components: [(1, 1, 1, 0)], lossless: true)
        writer.writeDHT(tables: [(0, 0, lengths, [1, 16])])
        if restartRows > 0 { writer.writeDRI(interval: width * restartRows) }
        writer.writeSOS(components: [(1, 0, 0)], spectralStart: 1, spectralEnd: 0)
        writer.writeEntropyData(entropy.data)
        writer.writeEOI()
        var parser = MarkerReader(data: writer.data)
        let parsed = try parser.parse()
        let decodedTable = try #require(parsed.scans.first?.dcTables[0])
        #expect(decodedTable.lookaheadLength[0] == 2)
        #expect(LosslessLookahead(table: decodedTable, sampleCount: width * height) == nil)
        return (writer.data, expected, parsed)
    }

    @Test(arguments: [2, 8, 12, 16])
    func paddedOutputMatchesFullPlaneAcrossRowAndRestartEdges(precision: Int) throws {
        for (width, height) in [(1, 16384), (16384, 1), (129, 129)] {
            for restartRows in [0, 1, 3] {
                let test = try fixture(width: width, height: height, precision: precision, restartRows: restartRows)
                let fullPlane = try JLIDecoder().decode(from: test.jpeg).data
                let widened = precision <= 8 ? fullPlane.flatMap { [$0, UInt8(0)] } : fullPlane
                #expect(widened == test.expected)
                let rowBytes = width * 2 + 5, offset = 3
                var storage = [UInt8](repeating: 0xA5, count: offset + height * rowBytes + 7)
                try storage.withUnsafeMutableBytes { bytes in
                    try JLIDecoder().decodeSharedLossless(test.parsed, into: .init(
                        bytes: .init(rebasing: bytes[offset..<(offset + height * rowBytes)]),
                        rowBytes: rowBytes, bytesPerSample: 2))
                }
                for y in 0..<height {
                    let start = offset + y * rowBytes
                    #expect(storage[start..<(start + width * 2)]
                        .elementsEqual(test.expected[(y * width * 2)..<((y + 1) * width * 2)]))
                    #expect(storage[(start + width * 2)..<(start + rowBytes)].allSatisfy { $0 == 0xA5 })
                }
                #expect(storage.prefix(offset).allSatisfy { $0 == 0xA5 })
                #expect(storage.suffix(7).allSatisfy { $0 == 0xA5 })
            }
        }
    }

    @Test func invalidStorageAndInterruptedScanPreserveBoundaries() throws {
        let width = 129, height = 129
        let test = try fixture(width: width, height: height, restartRows: 3)
        for (stride, count) in [(width * 2 - 1, width * height * 2),
                                (width * 2, width * height * 2 - 1), (Int.max, 64)] {
            var bytes = [UInt8](repeating: 0xA5, count: count)
            #expect(throws: JLIError.self) {
                try bytes.withUnsafeMutableBytes {
                    try JLIDecoder().decodeSharedLossless(test.parsed, into: .init(
                        bytes: $0, rowBytes: stride, bytesPerSample: 2))
                }
            }
            #expect(bytes.allSatisfy { $0 == 0xA5 })
        }
        let calls = Mutex(0)
        var bytes = [UInt8](repeating: 0xA5, count: width * height * 2 + 2)
        #expect(throws: CancellationError.self) {
            try bytes.withUnsafeMutableBytes { raw in
                try NativeOperation.withSynchronousCancellation({
                    if calls.withLock({ $0 += 1; return $0 }) == 4 { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 60)) {
                        try JLIDecoder().decodeSharedLossless(test.parsed, into: .init(
                            bytes: .init(rebasing: raw[1..<(raw.count - 1)]),
                            rowBytes: width * 2, bytesPerSample: 2))
                    }
                }
            }
        }
        #expect(bytes[0] == 0xA5 && bytes.last == 0xA5)
        #expect(bytes[1..<(1 + 2 * width * 2)].elementsEqual(test.expected.prefix(2 * width * 2)))
        #expect(bytes[(1 + 2 * width * 2)...].allSatisfy { $0 == 0xA5 })

        let restart = try #require((0..<(test.jpeg.count - 1)).first {
            test.jpeg[$0] == 0xFF && test.jpeg[$0 + 1] == 0xD0
        })
        var missing = test.jpeg
        missing.removeSubrange(restart..<(restart + 2))
        for malformed in [missing, Array(test.jpeg.prefix(restart)) + [0xFF, 0xD9]] {
            var parser = MarkerReader(data: malformed)
            let parsed = try parser.parse()
            var destination = [UInt8](repeating: 0xA5, count: width * height * 2 + 2)
            #expect(throws: JLIError.self) {
                try destination.withUnsafeMutableBytes { raw in
                    try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                        bytes: .init(rebasing: raw[1..<(raw.count - 1)]),
                        rowBytes: width * 2, bytesPerSample: 2))
                }
            }
            #expect(destination[0] == 0xA5 && destination.last == 0xA5)
            #expect(destination[(1 + 3 * width * 2)...].allSatisfy { $0 == 0xA5 })
        }
    }
}
