// SPDX-License-Identifier: Apache-2.0
import Testing
import Synchronization
@testable import SwiftJLI

@Suite struct LosslessRowStorageTests {
    @Test func narrowRowsObserveCancellationWithinBoundedSampleWork() throws {
        let width = 19, height = 100
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint8,
            colorModel: .grayscale, data: [UInt8](repeating: 42, count: width * height))
        var configuration = JLIEncoderConfiguration(lossless: true)
        configuration.losslessPrecision = 8
        let jpeg = try JLIEncoder().encode(image, configuration: configuration)
        var parser = MarkerReader(data: jpeg)
        let parsed = try parser.parse()
        let calls = Mutex(0)
        var output = [UInt8](repeating: 0xA5, count: width * height)
        #expect(throws: CancellationError.self) {
            try output.withUnsafeMutableBytes { raw in
                try NativeOperation.withSynchronousCancellation({
                    let n = calls.withLock { $0 += 1; return $0 }
                    if n >= 3 { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 60)) {
                        try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                            bytes: raw, rowBytes: width, bytesPerSample: 1))
                    }
                }
            }
        }
        // Cancellation after the first poll must stop partial decoding within
        // one bounded unit; no output outside that unit may be touched.
        let written = output.prefix(while: { $0 == 42 }).count
        #expect(written > 0 && written <= 1024)
        #expect(output.dropFirst(written).allSatisfy { $0 == 0xA5 })
    }

    /// Decode into an offset, odd-stride borrow and verify every byte outside
    /// the sample payload, including the final row padding, remains untouched.
    private func borrowed(_ jpeg: [UInt8], width: Int, height: Int, bps: Int) throws -> [UInt8] {
        var parser = MarkerReader(data: jpeg)
        let parsed = try parser.parse()
        let payload = width * bps, stride = payload + 7, offset = 3
        var storage = [UInt8](repeating: 0xA5, count: offset + height * stride + 5)
        try storage.withUnsafeMutableBytes { raw in
            try JLIDecoder().decodeSharedLossless(parsed, into: .init(
                bytes: .init(rebasing: raw[offset..<(offset + height * stride)]),
                rowBytes: stride, bytesPerSample: bps))
        }
        var result: [UInt8] = []
        for y in 0..<height {
            let start = offset + y * stride
            result += storage[start..<(start + payload)]
            #expect(storage[(start + payload)..<(start + stride)].allSatisfy { $0 == 0xA5 })
        }
        #expect(storage.prefix(offset).allSatisfy { $0 == 0xA5 })
        #expect(storage.suffix(5).allSatisfy { $0 == 0xA5 })
        return result
    }

    @Test(arguments: [2, 8, 12, 16])
    func allPredictorsPointTransformsAndRestartEdges(bits: Int) throws {
        for (width, height) in [(1, 1), (1, 7), (17, 1), (17, 7)] {
            let bps = bits <= 8 ? 1 : 2, mask = (1 << bits) - 1
            var source: [UInt8] = []
            for i in 0..<(width * height) {
                let value = i % 3 == 0 ? mask : i % 3 == 1 ? 0 : (i * 8191) & mask
                source.append(UInt8(truncatingIfNeeded: value))
                if bps == 2 { source.append(UInt8(value >> 8)) }
            }
            let image = try JLIImage(width: width, height: height,
                pixelFormat: bps == 1 ? .uint8 : .uint16, colorModel: .grayscale, data: source)
            for predictor in 1...7 {
                for pt in [0, min(3, bits - 1)] {
                    for rowsPerSegment in [0, 1, 2] {
                        var cfg = JLIEncoderConfiguration(lossless: true)
                        cfg.losslessPrecision = bits; cfg.losslessPredictor = predictor
                        cfg.losslessPointTransform = pt
                        cfg.restartInterval = width * rowsPerSegment
                        let jpeg = try JLIEncoder().encode(image, configuration: cfg)
                        // The full-plane native path remains independent of the
                        // new row history and is a useful arithmetic reference.
                        let packed = try JLIDecoder().decode(from: jpeg).data
                        #expect(try borrowed(jpeg, width: width, height: height, bps: bps) == packed)
                        if bps == 1 {
                            let widened = packed.flatMap { [$0, UInt8(0)] }
                            #expect(try borrowed(jpeg, width: width, height: height, bps: 2) == widened)
                        }
                    }
                }
            }
        }
    }

    @Test func independentCjpegFixturesMatchExactSamples() throws {
        // Provenance and original cjpeg/djpeg commands are recorded with the
        // existing fixtures in LosslessTests and LosslessRestartTests.
        for jpeg in [LosslessTests.llP1, LosslessTests.llP7] {
            #expect(try borrowed(jpeg, width: 16, height: 16, bps: 1) == LosslessTests.src)
        }
        #expect(try borrowed(LosslessTests.ll16, width: 6, height: 5, bps: 2) == LosslessTests.src16LE)
        #expect(try borrowed(LosslessTests.nlPt1, width: 8, height: 8, bps: 1) == LosslessTests.nlPt1Expected)
        #expect(try borrowed(LosslessTests.nlPt2, width: 8, height: 8, bps: 1) == LosslessTests.nlPt2Expected)
        #expect(try borrowed(LosslessRestartTests.cjpegRestart8, width: 13, height: 9, bps: 1)
            == LosslessRestartTests.expected8)
        let expected12 = LosslessRestartTests.expected12.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
        #expect(try borrowed(LosslessRestartTests.cjpegRestart12, width: 13, height: 9, bps: 2) == expected12)
    }

    @Test func truncatedEntropyMissingRestartsAndDeadlineStillThrow() throws {
        let original = LosslessRestartTests.cjpegRestart12
        let restart = try #require((0..<(original.count - 1)).first { original[$0] == 0xFF && original[$0 + 1] == 0xD0 })
        var missing = original
        missing.removeSubrange(restart..<(restart + 2))
        let truncated = Array(original.prefix(restart)) + [0xFF, 0xD9]
        for jpeg in [missing, truncated] {
            #expect(throws: JLIError.self) { try borrowed(jpeg, width: 13, height: 9, bps: 2) }
        }
        // Parse before installing the expired deadline so the check necessarily
        // exercises the row decoder, rather than the marker parser.
        var parser = MarkerReader(data: original)
        let parsed = try parser.parse()
        var output = [UInt8](repeating: 0, count: 13 * 9 * 2)
        #expect(throws: CodecError.self) {
            try output.withUnsafeMutableBytes { raw in
                try NativeOperation.$current.withValue(.init(seconds: Double.leastNonzeroMagnitude)) {
                    try JLIDecoder().decodeSharedLossless(parsed, into: .init(bytes: raw, rowBytes: 26, bytesPerSample: 2))
                }
            }
        }
    }
}
