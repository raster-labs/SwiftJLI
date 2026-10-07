// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct XYBFloatDecodeTests {
    @Test func fractionalSRGBMatchesNativeBeforeIntegerRounding() async throws {
        let w = 19, h = 13
        let source = try JLIImage(width: w, height: h, pixelFormat: .uint8, colorModel: .rgb,
            data: (0..<(w * h * 3)).map { UInt8(30 + ($0 * 13) % 190) })
        let jpeg = Data(try JLIEncoder().encode(source, configuration: .init(quality: 92, colorSpace: .xyb)))
        for backend in SwiftJLI.Decoder.capabilities.availableBackends { for scale in [1, 2, 4, 8] {
            let decoder = try SwiftJLI.Decoder(configuration: .init(scale: scale, sampleFormat: .float32NormalisedSRGB))
            let native = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                try JLIDecoder().decode(from: Array(jpeg), configuration: .init(outputPixelFormat: .float32, scale: scale))
            }
            let reference: [Float] = Data(native.data).withUnsafeBytes { raw in
                stride(from: 0, to: raw.count, by: 4).map {
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) / 255
                }
            }
            let decoded = try await decoder.decode(jpeg, options: .init(executionPolicy: .required(backend)))
            #expect(decoded.image.descriptor.sampleType == .floatingPoint && decoded.image.descriptor.storageBits == 32)
            #expect(decoded.image.descriptor.iccProfile == Data(SRGBICCProfile.data))
            #expect(decoded.report.sampleConversion == .rawSRGBToNormalisedFloat32)
            #expect(decoded.report.colourConversion == .xybToSRGB && decoded.report.fidelity == .lossy)
            #expect(try decoder.inspect(jpeg).descriptor.meaningfulBits == 8)
            try decoded.image.storage.withUnsafeBytes { raw in
                for i in reference.indices {
                    let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                    #expect(bits == reference[i].bitPattern)
                }
            }
            #expect(reference.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
            #expect(reference.contains { abs($0 * 255 - ($0 * 255).rounded()) > 0.001 })
            let row = native.width * 12 + 16
            let plane = try PlaneDescriptor(width: native.width, height: native.height, components: [0, 1, 2], offset: 8,
                sampleStride: 4, pixelStride: 12, rowBytes: row, byteCount: 8 + row * native.height)
            let descriptor = try ImageDescriptor(width: native.width, height: native.height, sampleType: .floatingPoint,
                storageBits: 32, meaningfulBits: 32, components: [.red, .green, .blue], colour: .rgb,
                planes: [plane], iccProfile: Data(SRGBICCProfile.data))
            let destination = try ImageDestination.allocate(descriptor: descriptor)
            let direct = try await decoder.decode(jpeg, into: destination, options: .init(executionPolicy: .required(backend)))
            #expect(direct.image.storage.allocationID == destination.storage.allocationID)
            #expect(direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty)
            try direct.image.storage.withUnsafeBytes { raw in
                for y in 0..<native.height {
                    for x in 0..<(native.width * 3) {
                        let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 8 + y * row + x * 4, as: UInt32.self))
                        #expect(bits == reference[y * native.width * 3 + x].bitPattern)
                    }
                    #expect(raw[(8 + y * row + native.width * 12)..<(8 + (y + 1) * row)].allSatisfy { $0 == 0 })
                }
            }
        } }
    }

    @Test func normalisationDoesNotInferOtherColourProfiles() async throws {
        let decoder = try SwiftJLI.Decoder(configuration: .init(sampleFormat: .float32NormalisedSRGB))
        for components in [1, 3] {
            let native = try JLIImage(width: 1, height: 1, pixelFormat: .uint8,
                colorModel: components == 1 ? .grayscale : .rgb, data: [UInt8](repeating: 128, count: components))
            let jpeg = Data(try JLIEncoder().encode(native))
            do { _ = try await decoder.decode(jpeg); Issue.record("Unknown sRGB interpretation was inferred") }
            catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        }
    }
}
