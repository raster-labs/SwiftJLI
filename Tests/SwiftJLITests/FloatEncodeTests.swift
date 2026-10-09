// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct FloatEncodeTests {
    @Test(arguments: [1, 3], [false, true])
    func explicitQuantisationMatchesIntegerEncoding(components: Int, progressive: Bool) async throws {
        // Independent expected quantisation includes clamps, endpoints and ties.
        let values: [Float] = [-1, 0, 0.5 / 255, 1 / 255, 127.5 / 255, 0.5, 1, 2]
        let expected: [UInt8] = [0, 0, 1, 1, 128, 128, 255, 255]
        let w = 19, h = 13, row = w * components * 4 + 12
        let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components), offset: 8,
            sampleStride: 4, pixelStride: components * 4, rowBytes: row, byteCount: 8 + row * h)
        let d = try ImageDescriptor(width: w, height: h, sampleType: .floatingPoint,
            storageBits: 32, meaningfulBits: 32, components: components == 1 ? [.grey] : [.red, .green, .blue],
            colour: components == 1 ? .greyscale : .rgb, planes: [p], iccProfile: Data([1, 2, 3]))
        let image = try ImageDestination.allocate(descriptor: d).write { raw in
            // Padding holds NaNs; accidentally consuming it must fail.
            raw.initializeMemory(as: UInt8.self, repeating: 0xFF)
            for y in 0..<h { for x in 0..<(w * components) {
                let bits = values[(y * w * components + x) % values.count].bitPattern
                for byte in 0..<4 { raw[8 + y * row + x * 4 + byte] = UInt8(truncatingIfNeeded: bits >> (8 * byte)) }
            } }
        }
        let reference = try JLIImage(width: w, height: h, pixelFormat: .uint8,
            colorModel: components == 1 ? .grayscale : .rgb,
            data: (0..<(w * h * components)).map { expected[$0 % expected.count] }, iccProfile: [1, 2, 3])
        for backend in SwiftJLI.Encoder.capabilities.availableBackends {
            let dct = DCTOptions(progressiveMode: progressive ? .successiveApproximation : .sequential,
                floatInputPolicy: .normalisedClampedToUInt8)
            let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: dct)))
            let encoded = try await encoder.encode(image, options: .init(executionPolicy: .required(backend)))
            let expectedJPEG = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                try JLIEncoder().encode(reference, configuration: dct.native)
            }
            #expect(encoded.data == Data(expectedJPEG))
            #expect(encoded.report.sampleConversion == .normalisedFloat32ClampedToUInt8)
            #expect(encoded.report.fidelity == .lossy && encoded.report.backend == backend)
            #expect(encoded.report.pixelAllocationCount == 0 && encoded.report.peakPixelBytes == 0)
            #expect(encoded.report.copyEvents.isEmpty)
            let info = try SwiftJLI.Decoder().inspect(encoded.data)
            #expect(info.descriptor.meaningfulBits == 8 && info.descriptor.iccProfile == d.iccProfile)
        }
    }

    @Test func floatInputRequiresPolicyAndFiniteValues() async throws {
        let p = try PlaneDescriptor(width: 1, height: 1, sampleStride: 4, pixelStride: 4, rowBytes: 4, byteCount: 4)
        let d = try ImageDescriptor(width: 1, height: 1, sampleType: .floatingPoint, storageBits: 32, meaningfulBits: 32, planes: [p])
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct:
            .init(floatInputPolicy: .normalisedClampedToUInt8))))
        for sample: Float in [.nan, .infinity, -.infinity, 0.5] {
            let image = try ImageDestination.allocate(descriptor: d).write { raw in
                for byte in 0..<4 { raw[byte] = UInt8(truncatingIfNeeded: sample.bitPattern >> (byte * 8)) }
            }
            if !sample.isFinite {
                do { _ = try await encoder.encode(image); Issue.record("Non-finite float accepted") }
                catch let error as CodecError { #expect(error.category == .invalidArgument) }
            }
            // Neither default lossless nor ordinary lossy authorises normalisation.
            for mode: CompressionMode in [.lossless, .lossy] {
                let rejecting = try SwiftJLI.Encoder(configuration: .init(mode: mode))
                await #expect(throws: CodecError.self) { try await rejecting.encode(image) }
            }
        }
        #expect(throws: CodecError.self) {
            try EncoderConfiguration(codecOptions: .init(dct: .init(floatInputPolicy: .normalisedClampedToUInt8)))
        }
        let integer = try ImageDestination.allocate(descriptor: .greyscale16(width: 1, height: 1)).writeUInt16 { _, _ in 0 }
        await #expect(throws: CodecError.self) { try await encoder.encode(integer) }
    }
}
