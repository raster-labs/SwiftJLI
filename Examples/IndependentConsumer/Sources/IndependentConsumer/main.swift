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
        print("Independent SwiftJLI consumer: lossless JPEG, precision and shared-storage checks passed.")
    }
}
