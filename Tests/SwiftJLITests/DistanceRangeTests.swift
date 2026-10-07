// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct DistanceRangeTests {
    @Test(arguments: [26.0, 1000.0, Double.greatestFiniteMagnitude], [1, 3])
    func finiteDistancesBeyondOldAdapterLimitEncode(distance: Double, components: Int) async throws {
        let w = 17, h = 9, row = w * components
        let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components),
            sampleStride: 1, pixelStride: components, rowBytes: row, byteCount: row * h)
        let d = try ImageDescriptor(width: w, height: h, storageBits: 8, meaningfulBits: 8,
            components: components == 1 ? [.grey] : [.red, .green, .blue],
            colour: components == 1 ? .greyscale : .rgb, planes: [p])
        let source = try ImageDestination.allocate(descriptor: d).write { bytes in
            for i in bytes.indices { bytes[i] = UInt8((i * 37 + i * i) & 255) }
        }
        for backend in Encoder.capabilities.availableBackends {
            for profile in 0..<(components == 3 ? 4 : 3) {
                let options = DCTOptions(distance: distance,
                    chromaSubsampling: profile == 3 ? .yuv444 : .yuv420,
                    progressiveMode: profile == 1 ? .successiveApproximation : .sequential,
                    jpegliAdaptiveQuantisation: profile == 2,
                    colourSpace: profile == 3 ? .xybFromSRGB : .yCbCr)
                let encoded = try await Encoder(configuration: .init(mode: .lossy,
                    codecOptions: .init(dct: options))).encode(source, options: .init(executionPolicy: .required(backend)))
                let decoded = try await Decoder().decode(encoded.data)
                #expect(decoded.image.descriptor.width == w && decoded.image.descriptor.height == h)
                #expect(decoded.image.descriptor.meaningfulBits == 8 && encoded.report.fidelity == .lossy)
                #expect(encoded.report.copyEvents.isEmpty && encoded.report.pixelAllocationCount == 0)
            }
        }
    }

    @Test func saturatedQuantTablesAreRepresentableAtExtremeFiniteDistance() {
        for chroma in [false, true] { for subsampled in [false, true] {
            let table = Quantization.perceptualQuantTable(distance: .greatestFiniteMagnitude,
                chroma: chroma, isYUV420: subsampled)
            #expect(table == [Int](repeating: 255, count: 64))
        } }
        for channel in 0..<3 {
            #expect(Quantization.perceptualQuantTableXYB(distance: .greatestFiniteMagnitude,
                channel: channel) == [Int](repeating: 255, count: 64))
        }
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity, -Double.infinity])
    func invalidDistanceStillRejects(distance: Double) throws {
        do {
            _ = try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct: .init(distance: distance)))
            Issue.record("Accepted non-finite or negative distance")
        } catch let error as CodecError { #expect(error.category == .invalidArgument) }
    }
}
