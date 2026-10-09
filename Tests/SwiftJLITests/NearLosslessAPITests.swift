// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct NearLosslessAPITests {
    @Test(arguments: [2, 8, 12, 16], [1, 2, 3, 7, 127, 255, 32767, Int.max])
    func pointTransformHonoursMaximumError(bits: Int, maximumError: Int) async throws {
        let width = 31, height = 5, mask = (1 << bits) - 1
        let descriptor = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: 70)
        let source = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { x, y in
            if x == 0 { return UInt16(mask) }; if x == 1 { return 0 }
            return UInt16(((x * 8191) ^ (y * 257)) & mask)
        }
        for predictor in 1...7 {
            let config = try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: maximumError),
                                                  codecOptions: .init(predictor: predictor, restartInterval: width * 2))
            let encoded = try await SwiftJLI.Encoder(configuration: config).encode(source)
            let pt = config.pointTransform(precision: bits), effectiveBound = (1 << pt) - 1
            #expect(pt > 0 && pt < bits && effectiveBound <= maximumError)
            #expect(encoded.encoding.mode == .nearLossless(maximumAbsoluteError: effectiveBound))
            #expect(encoded.report.fidelity == .boundedError(effectiveBound))
            let destination = try ImageDestination.allocate(descriptor: descriptor)
            let decoded = try await SwiftJLI.Decoder().decode(encoded.data, into: destination)
            #expect(decoded.report.fidelity == .boundedError(effectiveBound))
            #expect(decoded.image.storage.allocationID == destination.storage.allocationID)
            #expect(decoded.image.descriptor.meaningfulBits == bits)
            for y in 0..<height { for x in 0..<width {
                let original = try source.sampleUInt16(x: x, y: y)
                let actual = try decoded.image.sampleUInt16(x: x, y: y)
                #expect(actual == (original >> pt) << pt)
                #expect(abs(Int(actual) - Int(original)) <= maximumError)
            } }
            // Independent native entry must produce exactly the same stream;
            // sharing cannot change the samples the predictor actually reads.
            var native = JLIEncoderConfiguration.diagnosticLossless
            native.losslessPrecision = bits; native.losslessPointTransform = pt
            native.losslessPredictor = predictor; native.restartInterval = width * 2
            var packed: [UInt8] = []
            for y in 0..<height { for x in 0..<width {
                let v = try source.sampleUInt16(x: x, y: y)
                packed += [UInt8(truncatingIfNeeded: v), UInt8(v >> 8)]
            } }
            let legacy = try JLIImage(width: width, height: height, pixelFormat: .uint16, colorModel: .grayscale, data: packed)
            #expect(encoded.data == Data(try JLIEncoder().encode(legacy, configuration: native)))
        }
    }
}
