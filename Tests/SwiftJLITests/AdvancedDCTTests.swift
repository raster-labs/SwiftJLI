// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct AdvancedDCTTests {
    @Test(arguments: [1, 3], [false, true])
    func publicAdaptiveProfilesMatchNative(components: Int, jpegli: Bool) async throws {
        let w = 47, h = 35, row = w * components + 9
        let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components),
            sampleStride: 1, pixelStride: components, rowBytes: row, byteCount: row * h)
        let d = try ImageDescriptor(width: w, height: h, storageBits: 8, meaningfulBits: 8,
            components: components == 1 ? [.grey] : [.red, .green, .blue],
            colour: components == 1 ? .greyscale : .rgb, planes: [p])
        let packed = (0..<(w * h * components)).map { i in UInt8(truncatingIfNeeded: i * 97 + i / w * 31) }
        let image = try ImageDestination.allocate(descriptor: d).write { raw in
            for y in 0..<h { for x in 0..<(w * components) { raw[y * row + x] = packed[y * w * components + x] } }
        }
        let native = try JLIImage(width: w, height: h, pixelFormat: .uint8,
            colorModel: components == 1 ? .grayscale : .rgb, data: packed)
        for backend in SwiftJLI.Encoder.capabilities.availableBackends {
            for progressive in [false, true] {
                for sampling: ChromaSubsampling in [.yuv444, .yuv420] {
                    let opts = DCTOptions(quality: 83, chromaSubsampling: sampling,
                        progressiveMode: progressive ? .successiveApproximation : .sequential,
                        adaptiveQuantisationField: !jpegli, jpegliAdaptiveQuantisation: jpegli)
                    let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: opts)))
                    let encoded = try await encoder.encode(image, options: .init(executionPolicy: .required(backend)))
                    var expectedConfig = JLIEncoderConfiguration(quality: 83,
                        chromaSubsampling: sampling == .yuv444 ? .yuv444 : .yuv420,
                        progressive: progressive, progressiveMode: .successiveApproximation)
                    expectedConfig.adaptiveQuantField = !jpegli
                    expectedConfig.jpegliAdaptiveQuant = jpegli
                    let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                        try JLIEncoder().encode(native, configuration: expectedConfig)
                    }
                    #expect(encoded.data == Data(expected))
                    #expect(encoded.report.backend == backend && encoded.report.fidelity == .lossy)
                    #expect(encoded.report.copyEvents.isEmpty && encoded.report.pixelAllocationCount == 0)
                    let decoded = try await SwiftJLI.Decoder().decode(encoded.data)
                    #expect(decoded.image.descriptor.width == w && decoded.image.descriptor.height == h)
                }
            }
        }
    }

    @Test func adaptiveOptionsRejectInapplicableCombinations() async throws {
        #expect(throws: CodecError.self) {
            try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct: .init(adaptiveQuantisation: false, adaptiveQuantisationField: true)))
        }
        #expect(throws: CodecError.self) {
            try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct: .init(adaptiveQuantisationField: true, jpegliAdaptiveQuantisation: true)))
        }
        let d = try ImageDescriptor.greyscale16(width: 4, height: 4, meaningfulBits: 12)
        let source = try ImageDestination.allocate(descriptor: d).writeUInt16 { _, _ in 2048 }
        for jpegli in [false, true] {
            let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct:
                .init(adaptiveQuantisationField: !jpegli, jpegliAdaptiveQuantisation: jpegli))))
            do {
                _ = try await encoder.encode(source)
                Issue.record("12-bit input silently ignored an adaptive field")
            } catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        }
    }
}
