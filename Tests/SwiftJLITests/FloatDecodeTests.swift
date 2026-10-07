// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct FloatDecodeTests {
    @Test(arguments: [8, 12], [false, true])
    func explicitRawFloatOutputMatchesNative(bits: Int, progressive: Bool) async throws {
        let w = 19, h = 13, bps = bits == 8 ? 1 : 2
        var bytes = [UInt8](repeating: 0, count: w * h * bps)
        for i in 0..<(w * h) {
            let value = (i * 151 + 117) & ((1 << bits) - 1)
            bytes[i * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { bytes[i * bps + 1] = UInt8(value >> 8) }
        }
        let image = try JLIImage(width: w, height: h, pixelFormat: bits == 8 ? .uint8 : .uint16,
            colorModel: .grayscale, data: bytes)
        let encoded = try JLIEncoder().encode(image, configuration: .init(progressive: progressive))
        for backend in SwiftJLI.Decoder.capabilities.availableBackends { for scale in [1, 2, 4, 8] {
            let decoder = try SwiftJLI.Decoder(configuration: .init(scale: scale, sampleFormat: .float32RawSamples))
            #expect(try decoder.inspect(Data(encoded)).descriptor.meaningfulBits == bits)
            let reference = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                try JLIDecoder().decode(from: encoded, configuration: .init(outputPixelFormat: .float32, scale: scale))
            }
            let decoded = try await decoder.decode(Data(encoded), options: .init(executionPolicy: .required(backend)))
            #expect(decoded.image.descriptor.sampleType == .floatingPoint)
            #expect(decoded.image.descriptor.storageBits == 32 && decoded.image.descriptor.meaningfulBits == 32)
            #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == reference.data)
            let outW = reference.width, outH = reference.height, row = outW * 4 + 12
            let p = try PlaneDescriptor(width: outW, height: outH, offset: 8,
                sampleStride: 4, pixelStride: 4, rowBytes: row, byteCount: 8 + row * outH)
            let d = try ImageDescriptor(width: outW, height: outH, sampleType: .floatingPoint,
                storageBits: 32, meaningfulBits: 32, planes: [p])
            let destination = try ImageDestination.allocate(descriptor: d)
            let direct = try await decoder.decode(Data(encoded), into: destination, options: .init(executionPolicy: .required(backend)))
            #expect(direct.image.storage.allocationID == destination.storage.allocationID)
            #expect(direct.report.fidelity == .lossy && direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty)
            var largest: Float = 0
            try direct.image.storage.withUnsafeBytes { raw in
                for y in 0..<outH {
                    let start = 8 + y * row, length = outW * 4
                    #expect(raw[start..<(start + length)].elementsEqual(reference.data[(y * length)..<((y + 1) * length)]))
                    #expect(raw[(start + length)..<(start + row)].allSatisfy { $0 == 0 })
                    for x in 0..<outW {
                        let o = start + x * 4
                        let bits = UInt32(raw[o]) | UInt32(raw[o + 1]) << 8 | UInt32(raw[o + 2]) << 16 | UInt32(raw[o + 3]) << 24
                        let sample = Float(bitPattern: bits)
                        #expect(sample.isFinite)
                        largest = max(largest, sample)
                    }
                }
            }
            #expect(largest > 1, "Raw Float32 sample units must not be normalised to [0, 1]")
        } }
    }

    @Test func unsupportedFloatInterpretationsFailBeforeBorrowing() async throws {
        let decoder = try SwiftJLI.Decoder(configuration: .init(sampleFormat: .float32RawSamples))
        for (components, lossless, icc) in [(3, false, false), (1, true, false), (1, false, true)] {
            let image = try JLIImage(width: 8, height: 8, pixelFormat: .uint8,
                colorModel: components == 1 ? .grayscale : .rgb,
                data: [UInt8](repeating: 128, count: 64 * components), iccProfile: icc ? [1, 2, 3] : nil)
            var config = JLIEncoderConfiguration.default
            if lossless { config = .diagnosticLossless; config.losslessPrecision = 8 }
            let data = Data(try JLIEncoder().encode(image, configuration: config))
            let p = try PlaneDescriptor(width: 8, height: 8, sampleStride: 4, pixelStride: 4, rowBytes: 32, byteCount: 256)
            let d = try ImageDescriptor(width: 8, height: 8, sampleType: .floatingPoint, storageBits: 32, meaningfulBits: 32, planes: [p])
            let destination = try ImageDestination.allocate(descriptor: d)
            do { _ = try await decoder.decode(data, into: destination); Issue.record("Unsupported float interpretation was accepted") }
            catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
            _ = try destination.write { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        #expect(SwiftJLI.Decoder.capabilities.sampleTypes.contains(.floatingPoint))
        #expect(!SwiftJLI.Encoder.capabilities.sampleTypes.contains(.floatingPoint))
    }
}
