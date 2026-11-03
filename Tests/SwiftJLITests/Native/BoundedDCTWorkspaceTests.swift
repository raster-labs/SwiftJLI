// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct BoundedDCTWorkspaceTests {
    @Test func laterEntropyFailureInvalidatesStreamedDestination() throws {
        let width = 511, height = 509
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint8,
            colorModel: .grayscale, data: [UInt8](repeating: 128, count: width * height))
        let encoded = try JLIEncoder().encode(image)
        var parser = MarkerReader(data: encoded)
        let complete = try parser.parse()
        let scan = try #require(complete.scans.first)
        let sos = try #require((0..<(encoded.count - 3)).first { encoded[$0] == 0xFF && encoded[$0 + 1] == 0xDA })
        let entropyStart = sos + 2 + Int(encoded[sos + 2]) * 256 + Int(encoded[sos + 3])
        // Retain a valid envelope and enough entropy for more than one batch.
        let truncated = Array(encoded.prefix(entropyStart + scan.entropyData.count / 2)) + [0xFF, 0xD9]
        var truncatedParser = MarkerReader(data: truncated)
        let parsed = try truncatedParser.parse()
        var bytes = [UInt8](repeating: 0xA5, count: width * height)
        #expect(throws: JLIError.self) {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                try bytes.withUnsafeMutableBytes { raw in
                    _ = try JLIDecoder().decodeParsed(parsed, borrowedDestination: .init(
                        bytes: raw, rowBytes: width, bytesPerSample: 1))
                }
            }
        }
        #expect(bytes[0] == 128)
        #expect(bytes.last == 0xA5)

        let decoder = try Decoder()
        let descriptor = try decoder.inspect(Data(encoded)).descriptor
        let destination = try ImageDestination.allocate(descriptor: descriptor)
        let options = DecodeOptions(resourceLimits: try ResourceLimits(maximumWorkers: 8))
        #expect(throws: CodecError.self) {
            try decoder.decodeSynchronously(Data(truncated), into: destination, options: options, cancellationCheck: {})
        }
        // Partially written samples cannot be published or the lease reused.
        #expect(throws: CodecError.self) {
            try decoder.decodeSynchronously(Data(encoded), into: destination, options: options, cancellationCheck: {})
        }
    }

    @Test func directGreyscaleRejectsInvalidDestinationBeforeWriting() throws {
        let image = try JLIImage(width: 8, height: 9, pixelFormat: .uint8,
            colorModel: .grayscale, data: [UInt8](repeating: 128, count: 72))
        let encoded = try JLIEncoder().encode(image)
        var parser = MarkerReader(data: encoded)
        let parsed = try parser.parse()
        for layout in [(rowBytes: 7, count: 72), (rowBytes: 8, count: 1), (rowBytes: Int.max, count: 72)] {
            var bytes = [UInt8](repeating: 0xA5, count: layout.count)
            var rejected = false
            do {
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: .scalarCPU, maximumWorkers: 1)) {
                    try bytes.withUnsafeMutableBytes { raw in
                        _ = try JLIDecoder().decodeParsed(parsed, borrowedDestination: .init(
                            bytes: raw, rowBytes: layout.rowBytes, bytesPerSample: 1))
                    }
                }
            } catch { rejected = true }
            #expect(rejected)
            #expect(bytes.allSatisfy { $0 == 0xA5 })
        }
    }

    @Test(arguments: [8, 12])
    func tiledGreyscaleConversionPreservesTiesAndFloatBits(precision: Int) throws {
        let width = 19, height = 9, blocksPerRow = 3
        let maximum = Float((1 << precision) - 1)
        let values: [Float] = [0.5, 1.5, 2.5, -0.0, 0.499, maximum - 0.5, maximum, maximum + 1]
        var plane = [Float](repeating: 0, count: width * height)
        var blocks = [Float](repeating: 0, count: 6 * 64)
        for y in 0..<height { for x in 0..<width {
            let value = values[(x + y) % values.count]
            plane[y * width + x] = value
            blocks[((y / 8) * blocksPerRow + x / 8) * 64 + (y % 8) * 8 + x % 8] = value
        } }
        for floating in [false, true] {
            let bps = floating ? 4 : precision == 8 ? 1 : 2
            let rowBytes = width * bps + 5
            var expected = [UInt8](repeating: 0xA5, count: rowBytes * height)
            var actual = expected
            try expected.withUnsafeMutableBytes { raw in
                try SharedDCTStorage.write([(plane, width, height)], width: width, height: height,
                    precision: precision, floatOutput: floating,
                    into: .init(bytes: raw, rowBytes: rowBytes, bytesPerSample: bps))
            }
            try actual.withUnsafeMutableBytes { raw in
                try blocks.withUnsafeBufferPointer { pixels in
                    // Split the batches inside a block row, as 1024-block
                    // batches do whenever the block-grid width is not a divisor.
                    for range in [0..<2, 2..<6] {
                        try SharedDCTStorage.writeGreyscaleBlocks(
                            UnsafeBufferPointer(rebasing: pixels[(range.lowerBound * 64)..<(range.upperBound * 64)]),
                            firstBlock: range.lowerBound, blocksPerRow: blocksPerRow,
                            width: width, height: height, precision: precision, floatOutput: floating,
                            into: .init(bytes: raw, rowBytes: rowBytes, bytesPerSample: bps))
                    }
                }
            }
            #expect(actual == expected)
            if !floating {
                // Greyscale uses ties-away rounding: 0.5, 1.5, 2.5 become 1, 2, 3.
                #expect(actual[0] == 1 && actual[bps] == 2 && actual[2 * bps] == 3)
            } else {
                // The sign bit of -0.0 must survive Float32 output unchanged.
                #expect(actual[(3 * 4)..<(4 * 4)].elementsEqual([0, 0, 0, 0x80]))
            }
        }
    }

    @Test(arguments: [8, 12])
    func reusedWorkerScratchPreservesOddEdgesAndCallerPadding(precision: Int) throws {
        // 65 x 98 blocks span several 1024-block batches and do not divide
        // evenly among two or three workers. The final block has partial rows/columns.
        // Keep exact Float32 equality: changing vDSP batch dimensions can alter
        // rounding even when the worker ranges do not overlap.
        let width = 513, height = 777, bps = precision == 8 ? 1 : 2
        var source = [UInt8](repeating: 0, count: width * height * bps)
        for y in 0..<height { for x in 0..<width {
            let value = (x * 17 + y * 31 + x * y % 257) & ((1 << precision) - 1)
            source[(y * width + x) * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { source[(y * width + x) * bps + 1] = UInt8(value >> 8) }
        } }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: precision == 8 ? .uint8 : .uint16, colorModel: .grayscale, data: source)
        for progressive in [false, true] {
            let jpeg = try JLIEncoder().encode(image,
                configuration: .init(quality: 87, progressive: progressive))
            var parser = MarkerReader(data: jpeg)
            let parsed = try parser.parse()
            for floating in [false, true] {
                let bps = floating ? 4 : precision == 8 ? 1 : 2
                let configuration = JLIDecoderConfiguration(outputPixelFormat: floating ? .float32 : nil)
                let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 1)) {
                    try JLIDecoder().decodeParsed(parsed, configuration: configuration).data
                }
                for workers in [1, 2, 3] {
                    let rowBytes = width * bps + 7
                    var destination = [UInt8](repeating: 0xA5, count: 3 + rowBytes * height + 5)
                    try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: workers)) {
                        try destination.withUnsafeMutableBytes { raw in
                            _ = try JLIDecoder().decodeParsed(parsed, configuration: configuration, borrowedDestination: .init(
                                bytes: .init(rebasing: raw[3..<(3 + rowBytes * height)]),
                                rowBytes: rowBytes, bytesPerSample: bps))
                        }
                    }
                    for y in 0..<height {
                        let matches = destination[(3 + y * rowBytes)..<(3 + y * rowBytes + width * bps)]
                            .elementsEqual(expected[(y * width * bps)..<((y + 1) * width * bps)])
                        #expect(matches, "row \(y), workers \(workers), precision \(precision), Float32 \(floating), progressive \(progressive)")
                        #expect(destination[(3 + y * rowBytes + width * bps)..<(3 + (y + 1) * rowBytes)]
                            .allSatisfy { $0 == 0xA5 })
                    }
                    #expect(destination.prefix(3).allSatisfy { $0 == 0xA5 })
                    #expect(destination.suffix(5).allSatisfy { $0 == 0xA5 })
                }
            }
        }
    }
}
