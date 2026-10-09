// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct JPEGInspectionTests {
    private func image(bits: Int, components: Int) throws -> Image {
        let w = 17, h = 9, bps = bits > 8 ? 2 : 1, row = w * components * bps
        let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components),
            sampleStride: bps, pixelStride: components * bps, rowBytes: row, byteCount: row * h)
        let d = try ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
            components: components == 1 ? [.grey] : [.red, .green, .blue],
            colour: components == 1 ? .greyscale : .rgb, planes: [p])
        return try ImageDestination.allocate(descriptor: d).write { raw in
            for i in 0..<(w * h * components) {
                let v = (i * 79 + i * i) & ((1 << bits) - 1)
                raw[i * bps] = UInt8(truncatingIfNeeded: v)
                if bps == 2 { raw[i * bps + 1] = UInt8(v >> 8) }
            }
        }
    }

    @Test(arguments: [8, 12], [ChromaSubsampling.yuv444, .yuv422, .yuv420])
    func dctFeaturesAreEncodedRatherThanOutputGeometry(bits: Int, sampling: ChromaSubsampling) async throws {
        for mode in [ProgressiveMode.sequential, .spectralSelection, .successiveApproximation] {
            let encoder = try Encoder(configuration: .init(mode: .lossy,
                codecOptions: .init(restartInterval: 1, dct: .init(chromaSubsampling: sampling, progressiveMode: mode))))
            let encoded = try await encoder.encode(image(bits: bits, components: 3))
            let decoder = try Decoder(configuration: .init(scale: 8, sampleFormat: .float32RawSamples))
            let info = try decoder.inspectJPEG(encoded.data)
            let common = try decoder.inspect(encoded.data)
            #expect(info.imageInfo.descriptor == common.descriptor)
            #expect(info.width == 17 && info.height == 9 && info.componentCount == 3)
            #expect(info.bitsPerComponent == bits && info.isExtendedPrecision == (bits > 8))
            #expect(info.isProgressive == (mode != .sequential))
            #expect(info.codingProcess == (mode == .sequential ? .sequentialDCT : .progressiveDCT))
            #expect(info.scanCount == (mode == .sequential ? 1 : mode == .spectralSelection ? 4 : 10))
            #expect(info.restartInterval == 1 && info.predictor == nil && info.pointTransform == nil && !info.isXYB)
            let expected: JPEGChromaSubsampling = sampling == .yuv444 ? .yuv444 : sampling == .yuv422 ? .yuv422 : .yuv420
            #expect(info.chromaSubsampling == expected)
            #expect(info.componentSampling.map(\.horizontalFactor) == (sampling == .yuv444 ? [1,1,1] : [2,1,1]))
            #expect(info.componentSampling.map(\.verticalFactor) == (sampling == .yuv420 ? [2,1,1] : [1,1,1]))
            #expect(info.componentSampling.map(\.identifier) == [1,2,3])
        }
    }

    @Test func predictivePointTransformIsNotClaimedExact() async throws {
        let encoder = try Encoder(configuration: .init(mode: .nearLossless(maximumAbsoluteError: 3),
            codecOptions: .init(predictor: 4, restartInterval: 17)))
        let encoded = try await encoder.encode(image(bits: 16, components: 1))
        let info = try Decoder().inspectJPEG(encoded.data)
        #expect(info.codingProcess == .predictive && info.predictor == 4 && info.pointTransform == 2)
        #expect(info.chromaSubsampling == .greyscale && info.restartInterval == 17 && info.scanCount == 1)
        #expect(info.bitsPerComponent == 16 && !info.isProgressive && !info.isXYB)
        #expect(info.componentSampling.map(\.horizontalFactor) == [1])
    }

    @Test func recognisedXYBRemainsVisibleWhenAncillaryMetadataIsDiscarded() async throws {
        let encoder = try Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(chromaSubsampling: .yuv444, colourSpace: .xybFromSRGB))))
        let encoded = try await encoder.encode(image(bits: 8, components: 3))
        let info = try Decoder().inspectJPEG(encoded.data, options: .init(metadataPolicy: .discardAncillary))
        #expect(info.isXYB && info.chromaSubsampling == .yuv444 && !info.isProgressive)
        #expect(info.imageInfo.descriptor.iccProfile == Data(XYBICCProfile.data))
        #expect(info.imageInfo.descriptor.components == [.uninterpreted("X"), .uninterpreted("Y"), .uninterpreted("B")])
    }

    @Test func inspectionUsesExistingMalformedInputAndResourceChecks() async throws {
        let decoder = try Decoder()
        #expect(throws: CodecError.self) { try decoder.inspectJPEG(Data([0xFF, 0xD8, 0xFF])) }
        let encoded = try await Encoder().encode(image(bits: 8, components: 1))
        let limits = try ResourceLimits(maximumCompressedBytes: encoded.data.count - 1)
        do { _ = try decoder.inspectJPEG(encoded.data, options: .init(resourceLimits: limits)); Issue.record("Accepted over-budget JPEG") }
        catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
    }

    @Test func nonstandardSamplingKeepsItsExactFactors() async throws {
        let encoder = try Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(chromaSubsampling: .yuv444))))
        var bytes = Array(try await encoder.encode(image(bits: 8, components: 3)).data)
        let sof = try #require(bytes.indices.dropLast().first { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xC0 })
        bytes[sof + 11] = 0x12 // 4:4:0: chroma has half the luma's vertical resolution.
        // Only the header is changed: this checks structural inspection, not a
        // claim that the original entropy now decodes under the changed geometry.
        let info = try Decoder().inspectJPEG(Data(bytes))
        #expect(info.chromaSubsampling == .other)
        #expect(info.componentSampling.map(\.horizontalFactor) == [1,1,1])
        #expect(info.componentSampling.map(\.verticalFactor) == [2,1,1])
    }
}
