// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct UInt12InputTests {
    @Test func fusedReaderPreservesSamplesAndIgnoresPadding() throws {
        let values: [UInt16] = [0, 4095, 1, 2048, 4094, 17]
        var bytes = [UInt8](repeating: 0xff, count: 20)
        for i in values.indices {
            let p = (i / 3) * 10 + (i % 3) * 2
            bytes[p] = UInt8(truncatingIfNeeded: values[i]); bytes[p + 1] = UInt8(values[i] >> 8)
        }
        try bytes.withUnsafeBytes { raw in
            let planes = try SharedDCTStorage.read(.init(bytes: raw, rowBytes: 10),
                width: 3, height: 2, components: 1, precision: 12)
            #expect(planes.y == values.map(Float.init))
            #expect(planes.cb.isEmpty && planes.cr.isEmpty)
        }
    }

    @Test(arguments: [0, 2, 5])
    func outOfRangeSamplesRejectAtEveryPosition(_ index: Int) async throws {
        let descriptor = try ImageDescriptor.greyscale16(width: 3, height: 2, meaningfulBits: 12, rowBytes: 10)
        let image = try ImageDestination.allocate(descriptor: descriptor).write { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            let p = (index / 3) * 10 + (index % 3) * 2
            bytes[p + 1] = 0x10 // 4096: one above the allowed maximum.
        }
        for mode: CompressionMode in [.lossless, .lossy] {
            do {
                _ = try await Encoder(configuration: .init(mode: mode)).encode(image)
                Issue.record("Invalid UInt12 sample encoded")
            } catch let error as CodecError { #expect(error.category == .invalidArgument) }
        }
    }

    @Test func discardedUInt12AlphaStillRequiresValidPrecision() async throws {
        let plane = try PlaneDescriptor(width: 1, height: 1, components: [0, 1, 2, 3],
            sampleStride: 2, pixelStride: 8, rowBytes: 8, byteCount: 8)
        let d = try ImageDescriptor(width: 1, height: 1, storageBits: 16, meaningfulBits: 12,
            components: [.red, .green, .blue, .alpha], colour: .rgb, alpha: .straight, planes: [plane])
        let image = try ImageDestination.allocate(descriptor: d).write { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            bytes[7] = 0x10
        }
        let encoder = try Encoder(configuration: .init(mode: .lossy,
            codecOptions: .init(dct: .init(alphaPolicy: .discardStraightAlpha))))
        do {
            _ = try await encoder.encode(image)
            Issue.record("Invalid discarded alpha encoded")
        } catch let error as CodecError { #expect(error.category == .invalidArgument) }
    }
}
