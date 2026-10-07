// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct ColourInputTests {
    private func source(kind: String, bits: Int, width: Int, padding: Int = 13,
                        alpha: AlphaInterpretation = .straight, icc: Data? = nil,
                        alphaVariant: Int = 0, nonFiniteAlpha: Bool = false) throws -> (Image, JLIImage) {
        let nc = kind == "rgba" ? 4 : 3, h = 9, bps = bits == 32 ? 4 : bits == 12 ? 2 : 1
        let row = width * nc * bps + ((padding + bps - 1) / bps) * bps, prefix = 8
        let components: [ComponentRole] = kind == "rgba" ? [.red, .green, .blue, .alpha]
            : kind == "yCbCr" ? [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")] : [.red, .green, .blue]
        let p = try PlaneDescriptor(width: width, height: h, components: Array(0..<nc), offset: prefix,
            sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: prefix + row * h)
        let d = try ImageDescriptor(width: width, height: h, sampleType: bits == 32 ? .floatingPoint : .unsignedInteger,
            storageBits: bps * 8, meaningfulBits: bits, components: components,
            colour: kind == "yCbCr" ? .unknown : .rgb, alpha: kind == "rgba" ? alpha : .absent,
            planes: [p], iccProfile: icc)
        var packed = [UInt8](repeating: 0, count: width * h * nc * bps)
        for i in 0..<(width * h * nc) {
            let v = (i * 29 + i * i + (nc == 4 && i % 4 == 3 ? alphaVariant : 0)) & (bits == 12 ? 4095 : 255)
            let value = nonFiniteAlpha && bits == 32 && nc == 4 && i == 3 ? Float.nan.bitPattern
                : bits == 32 ? (Float(v) / 255).bitPattern : UInt32(v)
            for byte in 0..<bps { packed[i * bps + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
        }
        let image = try ImageDestination.allocate(descriptor: d).write { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0xFF) // Float padding is non-finite.
            for y in 0..<h { for x in 0..<(width * nc * bps) {
                raw[prefix + y * row + x] = packed[y * width * nc * bps + x]
            } }
        }
        let native = try JLIImage(width: width, height: h,
            pixelFormat: bits == 32 ? .float32 : bits == 12 ? .uint16 : .uint8,
            colorModel: kind == "rgba" ? .rgba : kind == "yCbCr" ? .yCbCr : .rgb, data: packed,
            iccProfile: icc.map { Array($0) })
        return (image, native)
    }

    @Test(arguments: [8, 12, 32], [1, 17])
    func rgbaUsesSourceStrideAndDiscardsOnlyExplicitAlpha(bits: Int, width: Int) async throws {
        let (image, native) = try source(kind: "rgba", bits: bits, width: width)
        let (changedAlpha, _) = try source(kind: "rgba", bits: bits, width: width, padding: 21, alphaVariant: 101)
        for backend in Encoder.capabilities.availableBackends {
            for sampling in [ChromaSubsampling.yuv444, .yuv422, .yuv420] {
                for mode in [ProgressiveMode.sequential, .spectralSelection, .successiveApproximation] {
                    let options = DCTOptions(chromaSubsampling: sampling, progressiveMode: mode,
                        floatInputPolicy: bits == 32 ? .normalisedClampedToUInt8 : .reject,
                        alphaPolicy: .discardStraightAlpha)
                    let encoder = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: options)))
                    let jpeg = try await encoder.encode(image, options: .init(executionPolicy: .required(backend)))
                    let variant = try await encoder.encode(changedAlpha, options: .init(executionPolicy: .required(backend)))
                    let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                        try JLIEncoder().encode(native, configuration: options.native)
                    }
                    #expect(jpeg.data == Data(expected) && jpeg.data == variant.data)
                    #expect(jpeg.report.alphaDiscarded && jpeg.report.pixelAllocationCount == 0 && jpeg.report.copyEvents.isEmpty)
                    #expect(jpeg.report.sampleConversion == (bits == 32 ? .normalisedFloat32ClampedToUInt8 : nil))
                    #expect(try Decoder().inspect(jpeg.data).descriptor.components == [.red, .green, .blue])
                }
            }
        }
    }

    @Test(arguments: [8, 32], [1, 19])
    func preconvertedYCbCrMatchesNativeWithoutAnRGBTransform(bits: Int, width: Int) async throws {
        let (image, native) = try source(kind: "yCbCr", bits: bits, width: width)
        let (padded, _) = try source(kind: "yCbCr", bits: bits, width: width, padding: 27)
        for backend in Encoder.capabilities.availableBackends {
            for sampling in [ChromaSubsampling.yuv444, .yuv422, .yuv420] {
                for mode in [ProgressiveMode.sequential, .successiveApproximation] {
                    let options = DCTOptions(chromaSubsampling: sampling, progressiveMode: mode,
                        floatInputPolicy: bits == 32 ? .normalisedClampedToUInt8 : .reject, sourceColourSpace: .yCbCr)
                    let encoder = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: options)))
                    let jpeg = try await encoder.encode(image, options: .init(executionPolicy: .required(backend)))
                    let variant = try await encoder.encode(padded, options: .init(executionPolicy: .required(backend)))
                    let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                        try JLIEncoder().encode(native, configuration: options.native)
                    }
                    #expect(jpeg.data == Data(expected) && jpeg.data == variant.data)
                    #expect(!jpeg.report.alphaDiscarded && jpeg.report.copyEvents.isEmpty && jpeg.report.pixelAllocationCount == 0)
                }
            }
        }
    }

    @Test(arguments: ["rgb", "rgba"], [8, 32])
    func explicitGreyscaleAndXYBRemainFused(kind: String, bits: Int) async throws {
        let (image, native) = try source(kind: kind, bits: bits, width: 17)
        for backend in Encoder.capabilities.availableBackends {
            for xyb in [false, true] {
                let options = DCTOptions(chromaSubsampling: xyb ? .yuv444 : .greyscale,
                    floatInputPolicy: bits == 32 ? .normalisedClampedToUInt8 : .reject,
                    colourSpace: xyb ? .xybFromSRGB : .yCbCr,
                    alphaPolicy: kind == "rgba" ? .discardStraightAlpha : .reject)
                let jpeg = try await Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: options)))
                    .encode(image, options: .init(executionPolicy: .required(backend)))
                let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                    try JLIEncoder().encode(native, configuration: options.native)
                }
                #expect(jpeg.data == Data(expected))
                #expect(jpeg.report.alphaDiscarded == (kind == "rgba"))
                #expect(jpeg.report.colourConversion == (xyb ? .sRGBToXYB : .rgbToGreyscale))
                #expect(jpeg.report.copyEvents.isEmpty && jpeg.report.pixelAllocationCount == 0)
                #expect(try Decoder().inspectJPEG(jpeg.data).componentCount == (xyb ? 3 : 1))
            }
        }
    }

    @Test func ambiguousOrUnqualifiedInterpretationsReject() async throws {
        let plain = try Encoder(configuration: .init(mode: .lossy))
        for kind in ["rgba", "yCbCr"] {
            let (image, _) = try source(kind: kind, bits: 8, width: 3)
            do { _ = try await plain.encode(image); Issue.record("Implicit colour/alpha policy accepted") }
            catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        }
        let discard = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: .init(alphaPolicy: .discardStraightAlpha))))
        let (premultiplied, _) = try source(kind: "rgba", bits: 8, width: 3, alpha: .premultiplied)
        do { _ = try await discard.encode(premultiplied); Issue.record("Discarded unqualified premultiplied alpha") }
        catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        for (kind, bits, icc) in [("rgb", 12, nil as Data?), ("rgb", 8, Data(SRGBICCProfile.data))] {
            let (image, _) = try source(kind: kind, bits: bits, width: 3, icc: icc)
            let encoder = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: .init(chromaSubsampling: .greyscale))))
            do { _ = try await encoder.encode(image); Issue.record("Unqualified greyscale interpretation accepted") }
            catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        }
        #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct:
            .init(chromaSubsampling: .greyscale, sourceColourSpace: .yCbCr))) }
        let (taggedYCbCr, _) = try source(kind: "yCbCr", bits: 8, width: 3, icc: Data(SRGBICCProfile.data))
        let ycbcrEncoder = try Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(sourceColourSpace: .yCbCr))))
        do { _ = try await ycbcrEncoder.encode(taggedYCbCr); Issue.record("Reinterpreted a source ICC profile") }
        catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        let (nonFinite, _) = try source(kind: "rgba", bits: 32, width: 3, nonFiniteAlpha: true)
        let floating = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct:
            .init(floatInputPolicy: .normalisedClampedToUInt8, alphaPolicy: .discardStraightAlpha))))
        do { _ = try await floating.encode(nonFinite); Issue.record("Accepted non-finite discarded alpha") }
        catch let error as CodecError { #expect(error.category == .invalidArgument) }
    }
}
