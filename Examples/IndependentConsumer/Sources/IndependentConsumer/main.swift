// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI

@main struct IndependentConsumer {
    static func main() async throws {
        let descriptor = try SwiftJLI.ImageDescriptor.greyscale16(
            width: 3, height: 2, meaningfulBits: 16, rowBytes: 8)
        let destination = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor)
        let image = try destination.writeUInt16 { x, y in
            [UInt16(0), 65535, 4095, 17, 1, 32768][y * 3 + x]
        }
        guard try image.sampleUInt16(x: 1, y: 0) == 65535,
              image.storage.allocationID == destination.storage.allocationID else {
            throw SwiftJLI.CodecError(.internalFailure, "Synthetic shared-storage check failed.")
        }
        let encoder = try SwiftJLI.Encoder(configuration: .default)
        let decoder = try SwiftJLI.Decoder(configuration: .init())
        guard encoder.capabilities.canEncode, decoder.capabilities.canDecode else {
            throw SwiftJLI.CodecError(.internalFailure, "Lossless JPEG capabilities are missing.")
        }
        let encoded = try await encoder.encode(image)
        let info = try decoder.inspect(encoded.data)
        guard info.descriptor.meaningfulBits == 16 else {
            throw SwiftJLI.CodecError(.internalFailure, "JPEG precision changed.")
        }
        let allocated = try await decoder.decode(encoded.data)
        let next = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor)
        let shared = try await decoder.decode(encoded.data, into: next)
        guard shared.image.storage.allocationID == next.storage.allocationID,
              shared.report.pixelAllocationCount == 0, shared.report.copyEvents.isEmpty else {
            throw SwiftJLI.CodecError(.internalFailure, "Shared decode changed storage.")
        }
        for y in 0..<2 { for x in 0..<3 {
            let expected = try image.sampleUInt16(x: x, y: y)
            guard try allocated.image.sampleUInt16(x: x, y: y) == expected,
                  try shared.image.sampleUInt16(x: x, y: y) == expected else {
                throw SwiftJLI.CodecError(.internalFailure, "Lossless sample mismatch.")
            }
        } }
        let dctDescriptor = try SwiftJLI.ImageDescriptor.greyscale16(width: 13, height: 9, meaningfulBits: 12, rowBytes: 28)
        let dctImage = try SwiftJLI.ImageDestination.allocate(descriptor: dctDescriptor).writeUInt16 { x, y in UInt16((x * 193 + y * 173) & 4095) }
        let lossy = try SwiftJLI.Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(progressiveMode: .successiveApproximation))))
        let dct = try await lossy.encode(dctImage, options: .init(executionPolicy: .scalarCPU))
        let dctDestination = try SwiftJLI.ImageDestination.allocate(descriptor: dctDescriptor)
        let restored = try await decoder.decode(dct.data, into: dctDestination)
        guard dct.encoding.mode == .lossy, restored.report.fidelity == .lossy,
              restored.image.descriptor.meaningfulBits == 12,
              restored.image.storage.allocationID == dctDestination.storage.allocationID,
              restored.report.pixelAllocationCount == 0 else {
            throw SwiftJLI.CodecError(.internalFailure, "Progressive DCT storage/fidelity check failed.")
        }
        let previewDecoder = try SwiftJLI.Decoder(configuration: .init(scale: 2, sampleFormat: .float32RawSamples))
        let preview = try await previewDecoder.decode(dct.data)
        guard preview.image.descriptor.width == 7, preview.image.descriptor.height == 5,
              preview.image.descriptor.sampleType == .floatingPoint,
              preview.image.descriptor.storageBits == 32,
              try previewDecoder.inspect(dct.data).descriptor.meaningfulBits == 12 else {
            throw SwiftJLI.CodecError(.internalFailure, "Explicit raw-float preview interpretation changed.")
        }
        let floatPlane = try SwiftJLI.PlaneDescriptor(width: 1, height: 1,
            sampleStride: 4, pixelStride: 4, rowBytes: 4, byteCount: 4)
        let floatDescriptor = try SwiftJLI.ImageDescriptor(width: 1, height: 1,
            sampleType: .floatingPoint, storageBits: 32, meaningfulBits: 32, planes: [floatPlane])
        let floatImage = try SwiftJLI.ImageDestination.allocate(descriptor: floatDescriptor).write { raw in
            let bits = Float(0.5).bitPattern
            for byte in 0..<4 { raw[byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
        }
        let floatEncoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(floatInputPolicy: .normalisedClampedToUInt8))))
        let floatEncoded = try await floatEncoder.encode(floatImage)
        guard floatEncoded.report.sampleConversion == .normalisedFloat32ClampedToUInt8,
              floatEncoded.report.fidelity == .lossy,
              try decoder.inspect(floatEncoded.data).descriptor.meaningfulBits == 8 else {
            throw SwiftJLI.CodecError(.internalFailure, "Explicit float quantisation was not reported.")
        }
        let rgbPlane = try SwiftJLI.PlaneDescriptor(width: 1, height: 1, components: [0, 1, 2],
            sampleStride: 1, pixelStride: 3, rowBytes: 3, byteCount: 3)
        let rgbDescriptor = try SwiftJLI.ImageDescriptor(width: 1, height: 1, storageBits: 8, meaningfulBits: 8,
            components: [.red, .green, .blue], colour: .rgb, planes: [rgbPlane])
        let rgbImage = try SwiftJLI.ImageDestination.allocate(descriptor: rgbDescriptor).write {
            $0.initializeMemory(as: UInt8.self, repeating: 128)
        }
        let xybEncoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(chromaSubsampling: .yuv444, colourSpace: .xybFromSRGB))))
        let xybJPEG = try await xybEncoder.encode(rgbImage)
        let xybInfo = try decoder.inspect(xybJPEG.data)
        let srgb = try await decoder.decode(xybJPEG.data)
        guard xybJPEG.report.colourConversion == .sRGBToXYB, srgb.report.colourConversion == .xybToSRGB,
              srgb.image.descriptor.iccProfile != nil,
              srgb.image.descriptor.iccProfile != xybInfo.descriptor.iccProfile,
              srgb.image.descriptor.components == [.red, .green, .blue] else {
            throw SwiftJLI.CodecError(.internalFailure, "XYB output colour interpretation is incorrect.")
        }
        print("Independent SwiftJLI consumer: predictive, progressive, raw-float preview, normalised float encoding and XYB colour passed.")
    }
}
