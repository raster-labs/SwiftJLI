import Foundation
import Testing
@testable import SwiftJLI

@Suite("Explicit external predictive component interpretation")
struct PredictiveColourInterpretationTests {
    private func image(yCbCr: Bool, bits: Int = 12) throws -> Image {
        let width = 5, height = 3, bytes = bits <= 8 ? 1 : 2
        let plane = try PlaneDescriptor(width: width, height: height, components: [0, 1, 2],
            sampleStride: bytes, pixelStride: 3 * bytes, rowBytes: width * 3 * bytes,
            byteCount: width * height * 3 * bytes)
        let descriptor = try ImageDescriptor(width: width, height: height,
            storageBits: bytes * 8, meaningfulBits: bits,
            components: yCbCr ? [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")]
                              : [.red, .green, .blue],
            colour: yCbCr ? .unknown : .rgb, planes: [plane])
        return try ImageDestination.allocate(descriptor: descriptor).write { raw in
            for index in 0..<(width * height * 3) {
                // Independent component-distinct values, including zero and maxima.
                let value = index == 0 ? 0 : index == 1 ? (1 << bits) - 1 : (index * 719 + 13) & ((1 << bits) - 1)
                raw[index * bytes] = UInt8(truncatingIfNeeded: value)
                if bytes == 2 { raw[index * bytes + 1] = UInt8(truncatingIfNeeded: value >> 8) }
            }
        }
    }

    @Test("Predictive coding preserves each component without colour conversion", arguments: [8, 12, 16])
    func preservesComponents(bits: Int) async throws {
        let source = try image(yCbCr: true, bits: bits)
        let rgb = try image(yCbCr: false, bits: bits)
        let encoder = try Encoder(configuration: .init(codecOptions: .init(predictiveSourceColourModel: .yCbCr)))
        let encoded = try await encoder.encode(source)
        let reference = try await Encoder().encode(rgb)
        // This is an explicit component-meaning choice, never a numerical transform.
        #expect(encoded.data == reference.data)
        let decoder = try Decoder(configuration: .init(predictiveSourceColourModel: .yCbCr))
        let info = try decoder.inspect(encoded.data)
        #expect(info.descriptor.components == source.descriptor.components)
        #expect(info.descriptor.colour == .unknown)
        let decoded = try await decoder.decode(encoded.data)
        #expect(decoded.report.fidelity == .exactSamples)
        #expect(decoded.report.colourConversion == nil)
        #expect(decoded.image.descriptor.components == source.descriptor.components)
        #expect(decoded.image.descriptor.meaningfulBits == bits)
        let expected = try source.storage.withUnsafeBytes { Data($0) }
        let actual = try decoded.image.storage.withUnsafeBytes { Data($0) }
        #expect(actual == expected)
    }

    @Test("External YCbCr interpretation is explicit and cannot select DCT")
    func rejectsImplicitOrWrongMode() async throws {
        let source = try image(yCbCr: true)
        await #expect(throws: CodecError.self) { try await Encoder().encode(source) }
        #expect(throws: CodecError.self) {
            try EncoderConfiguration(mode: .lossy, codecOptions: .init(predictiveSourceColourModel: .yCbCr))
        }
        let rgb = try image(yCbCr: false)
        let encoder = try Encoder(configuration: .init(codecOptions: .init(predictiveSourceColourModel: .yCbCr)))
        await #expect(throws: CodecError.self) { try await encoder.encode(rgb) }
    }

    @Test("Conflicting destination interpretation refuses before consuming its writer")
    func destinationInterpretation() async throws {
        let rgb = try image(yCbCr: false)
        let encoded = try await Encoder().encode(rgb)
        let destination = try ImageDestination.allocate(descriptor: rgb.descriptor)
        let external = try Decoder(configuration: .init(predictiveSourceColourModel: .yCbCr))
        await #expect(throws: CodecError.self) { try await external.decode(encoded.data, into: destination) }
        let recovered = try await Decoder().decode(encoded.data, into: destination)
        #expect(recovered.image.storage.allocationID == destination.storage.allocationID)
        #expect(try recovered.image.storage.withUnsafeBytes { Data($0) }
                == rgb.storage.withUnsafeBytes { Data($0) })
    }
}
