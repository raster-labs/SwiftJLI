// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct ScaledDecodeTests {
    @Test(arguments: [8, 12], [1, 3])
    func scaledDecodeMatchesNativeAndPreservesStorage(bits: Int, components: Int) async throws {
        let width = 31, height = 23, bps = bits == 8 ? 1 : 2
        var bytes = [UInt8](repeating: 0, count: width * height * components * bps)
        for i in 0..<(width * height * components) {
            let value = (i * 173 + i / width * 51) & ((1 << bits) - 1)
            bytes[i * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { bytes[i * bps + 1] = UInt8(value >> 8) }
        }
        let image = try JLIImage(width: width, height: height, pixelFormat: bits == 8 ? .uint8 : .uint16,
            colorModel: components == 1 ? .grayscale : .rgb, data: bytes)
        for progressive in [false, true] {
            let data = try JLIEncoder().encode(image, configuration: .init(progressive: progressive,
                progressiveMode: .successiveApproximation))
            for scale in [1, 2, 4, 8] {
                let decoder = try SwiftJLI.Decoder(configuration: .init(scale: scale))
                let info = try decoder.inspect(Data(data))
                #expect(info.descriptor.width == width && info.descriptor.height == height)
                let reference = try NativeOperation.$current.withValue(.init(seconds: 120)) {
                    try JLIDecoder().decode(from: data, configuration: .init(scale: scale))
                }
                let decoded = try await decoder.decode(Data(data), options: .init(executionPolicy: .scalarCPU))
                #expect(decoded.image.descriptor.width == reference.width && decoded.image.descriptor.height == reference.height)
                #expect(decoded.report.fidelity == .lossy)
                #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == reference.data)
                let w = reference.width, h = reference.height, row = w * components * bps + 8
                let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components), offset: 4,
                    sampleStride: bps, pixelStride: components * bps, rowBytes: row, byteCount: 4 + row * h)
                let d = try ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
                    components: components == 1 ? [.grey] : [.red, .green, .blue],
                    colour: components == 1 ? .greyscale : .rgb, planes: [p])
                let destination = try ImageDestination.allocate(descriptor: d)
                let shared = try await decoder.decode(Data(data), into: destination, options: .init(executionPolicy: .scalarCPU))
                #expect(shared.image.storage.allocationID == destination.storage.allocationID)
                #expect(shared.report.pixelAllocationCount == 0 && shared.report.copyEvents.isEmpty)
                try shared.image.storage.withUnsafeBytes { raw in
                    for y in 0..<h {
                        let length = w * components * bps, start = 4 + y * row
                        #expect(raw[start..<(start + length)].elementsEqual(reference.data[(y * length)..<((y + 1) * length)]))
                        #expect(raw[(start + length)..<(start + row)].allSatisfy { $0 == 0 })
                    }
                }
            }
        }
    }

    @Test func previewsStillAdmitFullFrameWorkspace() async throws {
        let native = try JLIImage(width: 64, height: 64, pixelFormat: .uint8, colorModel: .grayscale,
            data: (0..<4096).map { UInt8(truncatingIfNeeded: $0 * 97) })
        let data = Data(try JLIEncoder().encode(native))
        let smallBudget = 64 * data.count + 1_048_576 + 128 * 64 + 1
        let limits = try ResourceLimits(maximumWorkspaceBytes: smallBudget)
        let decoder = try SwiftJLI.Decoder(configuration: .init(scale: 8))
        do {
            _ = try await decoder.decode(data, options: .init(resourceLimits: limits))
            Issue.record("Preview size bypassed full coefficient workspace admission")
        } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        for invalid in [0, 3, -1, Int.max] {
            #expect(throws: CodecError.self) { try SwiftJLI.Decoder(configuration: .init(scale: invalid)) }
        }
        let d = try ImageDescriptor.greyscale16(width: 2, height: 2)
        let image = try ImageDestination.allocate(descriptor: d).writeUInt16 { _, _ in 500 }
        let lossless = try await SwiftJLI.Encoder().encode(image)
        await #expect(throws: CodecError.self) { try await decoder.decode(lossless.data) }
        #expect(try decoder.inspect(lossless.data).descriptor.width == 2)
    }
}
