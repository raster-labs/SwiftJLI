// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import SwiftJLI

@Suite struct XYBAPITests {
    @Test(arguments: [8, 32], [1, 19])
    func sharedXYBMatchesNativeAndDescribesSRGB(storageBits: Int, width: Int) async throws {
        let h = 13, bps = storageBits / 8, row = width * 3 * bps + 12
        let p = try PlaneDescriptor(width: width, height: h, components: [0, 1, 2], offset: 8,
            sampleStride: bps, pixelStride: 3 * bps, rowBytes: row, byteCount: 8 + row * h)
        let d = try ImageDescriptor(width: width, height: h,
            sampleType: storageBits == 8 ? .unsignedInteger : .floatingPoint,
            storageBits: storageBits, meaningfulBits: storageBits, components: [.red, .green, .blue],
            colour: .rgb, planes: [p])
        let packed = (0..<(width * h * 3)).map { UInt8(40 + ($0 * 17) % 170) }
        let image = try ImageDestination.allocate(descriptor: d).write { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0xFF)
            for y in 0..<h { for x in 0..<(width * 3) {
                let value = packed[y * width * 3 + x], offset = 8 + y * row + x * bps
                if bps == 1 { raw[offset] = value }
                else {
                    let bits = (Float(value) / 255).bitPattern
                    for byte in 0..<4 { raw[offset + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
                }
            } }
        }
        let native = try JLIImage(width: width, height: h, pixelFormat: .uint8, colorModel: .rgb, data: packed)
        for backend in SwiftJLI.Encoder.capabilities.availableBackends {
            let options = DCTOptions(quality: 93, chromaSubsampling: .yuv444,
                floatInputPolicy: bps == 4 ? .normalisedClampedToUInt8 : .reject, colourSpace: .xybFromSRGB)
            let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: options)))
            let jpeg = try await encoder.encode(image, options: .init(executionPolicy: .required(backend)))
            let reference = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                try JLIEncoder().encode(native, configuration: options.native)
            }
            #expect(jpeg.data == Data(reference))
            #expect(jpeg.report.colourConversion == .sRGBToXYB && jpeg.report.fidelity == .lossy)
            #expect(jpeg.report.sampleConversion == (bps == 4 ? .normalisedFloat32ClampedToUInt8 : nil))
            #expect(jpeg.report.pixelAllocationCount == 0 && jpeg.report.copyEvents.isEmpty)
            let info = try SwiftJLI.Decoder().inspect(jpeg.data)
            #expect(info.descriptor.iccProfile == Data(XYBICCProfile.data))
            #expect(info.descriptor.components == [.uninterpreted("X"), .uninterpreted("Y"), .uninterpreted("B")])
            for scale in [1, 2, 4, 8] {
                let decoder = try SwiftJLI.Decoder(configuration: .init(scale: scale))
                let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                    try JLIDecoder().decode(from: reference, configuration: .init(scale: scale))
                }
                let decoded = try await decoder.decode(jpeg.data, options: .init(executionPolicy: .required(backend)))
                #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == expected.data)
                #expect(decoded.image.descriptor.iccProfile == Data(SRGBICCProfile.data))
                #expect(decoded.image.descriptor.components == [.red, .green, .blue])
                #expect(decoded.report.colourConversion == .xybToSRGB)
                let w = expected.width, height = expected.height, stride = w * 3 + 7
                let plane = try PlaneDescriptor(width: w, height: height, components: [0, 1, 2],
                    sampleStride: 1, pixelStride: 3, rowBytes: stride, byteCount: stride * height)
                let descriptor = try ImageDescriptor(width: w, height: height, storageBits: 8, meaningfulBits: 8,
                    components: [.red, .green, .blue], colour: .rgb, planes: [plane], iccProfile: Data(SRGBICCProfile.data))
                let destination = try ImageDestination.allocate(descriptor: descriptor)
                let direct = try await decoder.decode(jpeg.data, into: destination, options: .init(executionPolicy: .required(backend)))
                #expect(direct.image.storage.allocationID == destination.storage.allocationID)
                #expect(direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty)
                try direct.image.storage.withUnsafeBytes { raw in
                    for y in 0..<height {
                        #expect(raw[(y * stride)..<(y * stride + w * 3)].elementsEqual(expected.data[(y * w * 3)..<((y + 1) * w * 3)]))
                        #expect(raw[(y * stride + w * 3)..<((y + 1) * stride)].allSatisfy { $0 == 0 })
                    }
                }
            }
        }
    }

    @Test func unknownProfilesAndIgnoredXYBOptionsAreRejected() async throws {
        for dct in [DCTOptions(colourSpace: .xybFromSRGB),
                    DCTOptions(chromaSubsampling: .yuv444, progressiveMode: .spectralSelection, colourSpace: .xybFromSRGB),
                    DCTOptions(chromaSubsampling: .yuv444, perceptualQuantisationTables: false, colourSpace: .xybFromSRGB),
                    DCTOptions(chromaSubsampling: .yuv444, jpegliAdaptiveQuantisation: true, colourSpace: .xybFromSRGB)] {
            #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct: dct)) }
        }
        let dct = DCTOptions(chromaSubsampling: .yuv444, colourSpace: .xybFromSRGB)
        #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .lossy, codecOptions: .init(restartInterval: 1, dct: dct)) }
        let p = try PlaneDescriptor(width: 1, height: 1, components: [0, 1, 2], sampleStride: 1, pixelStride: 3, rowBytes: 3, byteCount: 3)
        let d = try ImageDescriptor(width: 1, height: 1, storageBits: 8, meaningfulBits: 8,
            components: [.red, .green, .blue], colour: .rgb, planes: [p], iccProfile: Data([1, 2, 3]))
        let image = try ImageDestination.allocate(descriptor: d).write { $0.initializeMemory(as: UInt8.self, repeating: 128) }
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: dct)))
        await #expect(throws: CodecError.self) { try await encoder.encode(image) }
        let native = try JLIImage(width: 1, height: 1, pixelFormat: .uint8, colorModel: .rgb, data: [128, 128, 128])
        var jpeg = try JLIEncoder().encode(native, configuration: dct.native)
        let wrongDescriptor = try ImageDescriptor(width: 1, height: 1, storageBits: 8, meaningfulBits: 8,
            components: [.red, .green, .blue], colour: .rgb, planes: [p], iccProfile: Data(XYBICCProfile.data))
        let wrongDestination = try ImageDestination.allocate(descriptor: wrongDescriptor)
        await #expect(throws: CodecError.self) {
            try await SwiftJLI.Decoder().decode(Data(jpeg), into: wrongDestination)
        }
        _ = try wrongDestination.write { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        let rawFloat = try SwiftJLI.Decoder(configuration: .init(sampleFormat: .float32RawSamples))
        await #expect(throws: CodecError.self) { try await rawFloat.decode(Data(jpeg)) }
        // APP14 transform byte: recognise the profile and interpretation together.
        #expect(jpeg[3] == 0xEE)
        let end = 4 + Int(jpeg[4]) * 256 + Int(jpeg[5])
        #expect(jpeg[end + 1] == 0xE2)
        var unknownProfile = jpeg
        unknownProfile[end + 18 + 36] ^= 1
        #expect(throws: CodecError.self) { try SwiftJLI.Decoder().inspect(Data(unknownProfile)) }
        jpeg[end - 1] = 1
        #expect(throws: CodecError.self) { try SwiftJLI.Decoder().inspect(Data(jpeg)) }
    }

    @Test func embeddedSRGBProfileMatchesOriginal() throws {
        #expect(RegressionCorpusTests.sha256(SRGBICCProfile.data) == "384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a")
        #expect(SRGBICCProfile.data.count == 3024)
    }

    #if canImport(CoreGraphics)
    @Test func outputProfileAgreesWithSystemSRGB() throws {
        let embedded = try #require(CGColorSpace(iccData: Data(SRGBICCProfile.data) as CFData))
        let system = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var comparisons = 0
        for r in stride(from: 0, through: 255, by: 51) {
            for g in stride(from: 0, through: 255, by: 51) {
                for b in stride(from: 0, through: 255, by: 51) {
                    let values = [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1]
                    let colour = try #require(CGColor(colorSpace: embedded, components: values))
                    let converted = try #require(colour.converted(to: system, intent: .relativeColorimetric, options: nil))
                    let actual = try #require(converted.components)
                    for c in 0..<3 { #expect(abs(actual[c] - values[c]) < 1.0 / 255) }
                    comparisons += 1
                }
            }
        }
        #expect(comparisons == 216)
    }
    #endif
}
