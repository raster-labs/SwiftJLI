// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct ZeroRunLosslessTests {
    @Test(arguments: [2, 8, 12, 16])
    func constantAndChangingPlateausPreserveSamplesAndPadding(bits: Int) throws {
        let width = 129, height = 131, bps = bits <= 8 ? 1 : 2
        let mask = (1 << bits) - 1
        for plateau in [false, true] {
            var source: [UInt8] = []
            for y in 0..<height { for x in 0..<width {
                let value = plateau ? ((x / 31 + y / 17) * 19) & mask : mask / 2
                source.append(UInt8(truncatingIfNeeded: value))
                if bps == 2 { source.append(UInt8(value >> 8)) }
            } }
            let image = try JLIImage(width: width, height: height,
                pixelFormat: bps == 1 ? .uint8 : .uint16, colorModel: .grayscale, data: source)
            for pt in [0, min(3, bits - 1)] { for rowsPerSegment in [0, 1, 3] {
                var configuration = JLIEncoderConfiguration(lossless: true)
                configuration.losslessPrecision = bits
                configuration.losslessPointTransform = pt
                configuration.losslessPredictor = 1
                configuration.restartInterval = width * rowsPerSegment
                let jpeg = try JLIEncoder().encode(image, configuration: configuration)
                var markerReader = MarkerReader(data: jpeg)
                let parsed = try markerReader.parse()
                let table = try #require(parsed.scans[0].dcTables[0])
                #expect(table.lookaheadLength[0] == 1 && table.lookaheadSymbol[0] == 0)
                let expected = try JLIDecoder().decode(from: jpeg).data
                let stride = width * bps + 7
                var destination = [UInt8](repeating: 0xA5, count: 3 + height * stride + 5)
                try destination.withUnsafeMutableBytes {
                    try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                        bytes: .init(rebasing: $0[3..<(3 + height * stride)]),
                        rowBytes: stride, bytesPerSample: bps))
                }
                for y in 0..<height {
                    #expect(destination[(3 + y * stride)..<(3 + y * stride + width * bps)]
                        .elementsEqual(expected[(y * width * bps)..<((y + 1) * width * bps)]))
                    #expect(destination[(3 + y * stride + width * bps)..<(3 + (y + 1) * stride)]
                        .allSatisfy { $0 == 0xA5 })
                }
                #expect(destination.prefix(3).allSatisfy { $0 == 0xA5 })
                #expect(destination.suffix(5).allSatisfy { $0 == 0xA5 })
            } }
        }
    }

    @Test func zeroRunsRetainReadBitsAndRestartBoundaries() throws {
        let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [0, 1])
        for offset in 0..<64 { for length in [1, 7, 8, 9, 63, 64, 65, 127, 129] {
            var writer = BitWriter()
            for _ in 0..<offset { writer.writeBits(1, count: 1) }
            for _ in 0..<length { HuffmanEncoder.encodeDC(0, table: table, writer: &writer) }
            HuffmanEncoder.encodeDC(-1, table: table, writer: &writer)
            writer.emitRestartMarker(0)
            writer.writeBits(0x5A, count: 8); writer.flush()
            var reader = BitReader(data: writer.data)
            for _ in 0..<offset { #expect(try reader.readBits(1) == 1) }
            var remaining = length
            while remaining > 0 {
                let consumed = reader.consumeZeroDifferences(table, maximum: remaining)
                try #require(consumed > 0 && consumed <= remaining)
                remaining -= consumed
            }
            #expect(reader.consumeZeroDifferences(table, maximum: 1) == 0)
            #expect(try HuffmanDecoder.decodeDC(from: &reader, table: table) == -1)
            try reader.skipRestartMarker(expectedIndex: 0)
            #expect(try reader.readBits(8) == 0x5A)
        } }
    }

    @Test func malformedExtentsEntropyAndDeadlineReject() throws {
        let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [0, 1])
        for (width, height) in [(0, 1), (1, Int.min), (Int.max, 2), (8, 2)] {
            var output = [UInt8](repeating: 0xA5, count: 16)
            var reader = BitReader(data: [])
            #expect(throws: JLIError.self) {
                try output.withUnsafeMutableBytes {
                    try ZeroRunLosslessDecoder.decode(into: .init(bytes: $0, rowBytes: 16, bytesPerSample: 2),
                        width: width, height: height, half: 2048, table: table, reader: &reader,
                        pointTransform: 0, segmentRows: 1)
                }
            }
            #expect(output.allSatisfy { $0 == 0xA5 })
        }
        for entropy: [UInt8] in [[], [0], [0, 0], [255, 217], [255]] {
            var output = [UInt8](repeating: 0xA5, count: 35)
            var reader = BitReader(data: entropy)
            #expect(throws: JLIError.self) {
                try output.withUnsafeMutableBytes {
                    try ZeroRunLosslessDecoder.decode(into: .init(bytes: .init(rebasing: $0[1..<33]), rowBytes: 16, bytesPerSample: 2),
                        width: 8, height: 2, half: 2048, table: table, reader: &reader,
                        pointTransform: 0, segmentRows: 1)
                }
            }
            #expect(output[0] == 0xA5 && output.suffix(2).allSatisfy { $0 == 0xA5 })
        }
        var output = [UInt8](repeating: 0xA5, count: 16)
        var reader = BitReader(data: [0])
        #expect(throws: CodecError.self) {
            try NativeOperation.$current.withValue(.init(seconds: Double.leastNonzeroMagnitude)) {
                try output.withUnsafeMutableBytes {
                    try ZeroRunLosslessDecoder.decode(into: .init(bytes: $0, rowBytes: 16, bytesPerSample: 2),
                        width: 8, height: 1, half: 2048, table: table, reader: &reader,
                        pointTransform: 0, segmentRows: 1)
                }
            }
        }
        #expect(output.allSatisfy { $0 == 0xA5 })
    }
}
