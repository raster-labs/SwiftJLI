// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct LossyAPITests {
    @Test(arguments: [8, 12], [1, 3])
    func publicDCTRoundTripAndDirectStorage(bits: Int, nc: Int) async throws {
        let w = 19, h = 17, bps = bits == 8 ? 1 : 2, row = w * nc * bps + 8
        let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<nc), offset: 4,
            sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: 4 + row * h)
        let descriptor = try ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
            components: nc == 1 ? [.grey] : [.red, .green, .blue], colour: nc == 1 ? .greyscale : .rgb, planes: [p])
        let source = try ImageDestination.allocate(descriptor: descriptor).write { raw in
            for y in 0..<h { for x in 0..<(w * nc) {
                let v = (x * 101 + y * 193) & ((1 << bits) - 1), o = 4 + y * row + x * bps
                raw[o] = UInt8(truncatingIfNeeded: v)
                if bps == 2 { raw[o + 1] = UInt8(v >> 8) }
            } }
        }
        for subsampling: ChromaSubsampling in [.yuv444, .yuv422, .yuv420] {
            for mode: ProgressiveMode in [.sequential, .spectralSelection, .successiveApproximation] {
                let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy,
                    codecOptions: .init(restartInterval: 3, dct: .init(chromaSubsampling: subsampling, progressiveMode: mode))))
                let encoded = try await encoder.encode(source, options: .init(executionPolicy: .scalarCPU))
                #expect(encoded.encoding.mode == .lossy && encoded.report.fidelity == .lossy)
                #expect(encoded.report.pixelAllocationCount == 0 && encoded.report.copyEvents.isEmpty)
                let decoder = try SwiftJLI.Decoder()
                let info = try decoder.inspect(encoded.data)
                #expect(info.descriptor.meaningfulBits == bits)
                let allocated = try await decoder.decode(encoded.data, options: .init(executionPolicy: .scalarCPU))
                let owner = try OwnedImageStorage(byteCount: descriptor.requiredByteCount)
                let destination = try ImageDestination(descriptor: descriptor, storage: owner)
                let direct = try await decoder.decode(encoded.data, into: destination, options: .init(executionPolicy: .scalarCPU))
                #expect(direct.image.storage.allocationID == owner.allocationID)
                #expect(direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty && direct.report.fidelity == .lossy)
                try direct.image.storage.withUnsafeBytes { out in
                    try allocated.image.storage.withUnsafeBytes { packed in
                        for y in 0..<h {
                            #expect(out[(4 + y * row)..<(4 + y * row + w * nc * bps)].elementsEqual(packed[(y * w * nc * bps)..<((y + 1) * w * nc * bps)]))
                            #expect(out[(4 + y * row + w * nc * bps)..<(4 + (y + 1) * row)].allSatisfy { $0 == 0 })
                        }
                    }
                }
                #expect(allocated.report.pixelAllocationCount == 1)
            }
        }
    }

    @Test func explicitOptionsAndUnsupportedPrecision() async throws {
        #expect(throws: CodecError.self) { try EncoderConfiguration(codecOptions: .init(dct: .init(quality: 80))) }
        #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .lossy, codecOptions: .init(predictor: 3)) }
        for v in [Double.nan, .infinity, -1, 101] {
            #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .lossy, codecOptions: .init(dct: .init(quality: v))) }
        }
        let d = try ImageDescriptor.greyscale16(width: 2, height: 2, meaningfulBits: 16)
        let image = try ImageDestination.allocate(descriptor: d).write { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy))
        await #expect(throws: CodecError.self) { try await encoder.encode(image) }
    }

    @Test func backendReportMatchesActualChoice() async throws {
        let plane = try PlaneDescriptor(width: 8, height: 8, components: [0], sampleStride: 1, pixelStride: 1, rowBytes: 8, byteCount: 64)
        let d = try ImageDescriptor(width: 8, height: 8, storageBits: 8, meaningfulBits: 8, components: [.grey], colour: .greyscale, planes: [plane])
        let image = try ImageDestination.allocate(descriptor: d).write { $0.initializeMemory(as: UInt8.self, repeating: 127) }
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy))
        let preferred = try await encoder.encode(image, options: .init(executionPolicy: .preferred(.accelerated)))
        #if canImport(Accelerate)
        #expect(preferred.report.backend == .accelerated && preferred.report.fallbackReason == nil)
        let required = try await encoder.encode(image, options: .init(executionPolicy: .required(.accelerated)))
        #expect(required.report.backend == .accelerated)
        #else
        #expect(preferred.report.backend == .scalarCPU && preferred.report.fallbackReason != nil)
        await #expect(throws: CodecError.self) { try await encoder.encode(image, options: .init(executionPolicy: .required(.accelerated))) }
        #endif
        let scalar = try await encoder.encode(image, options: .init(executionPolicy: .required(.scalarCPU)))
        #expect(scalar.report.backend == .scalarCPU)
        let decoded = try await SwiftJLI.Decoder().decode(scalar.data, options: .init(executionPolicy: .preferred(.accelerated)))
        #expect(decoded.report.backend == preferred.report.backend)
    }
    @Test func malformedDCTMutationsStayWithinPublicErrors() async throws {
        let image = try JLIImage(width: 13, height: 11, pixelFormat: .uint8, colorModel: .grayscale,
            data: (0..<143).map { UInt8(truncatingIfNeeded: $0 * 101) })
        let decoder = try SwiftJLI.Decoder()
        for progressive in [false, true] {
            let original = try JLIEncoder().encode(image, configuration: .init(progressive: progressive))
            // Exercise structural fields, table symbols and entropy, retaining a
            // complete stream so decode reaches the DCT kernel when appropriate.
            for offset in original.indices {
                var bytes = original
                bytes[offset] ^= 0xFF
                do { _ = try await decoder.decode(Data(bytes), options: .init(executionPolicy: .scalarCPU)) }
                catch is CodecError { }
                catch { Issue.record("Unexpected public error: \(error)") }
            }
            for length in stride(from: 0, to: original.count, by: 7) {
                #expect(throws: CodecError.self) { try decoder.inspect(Data(original.prefix(length))) }
            }
        }
    }

    @Test func DCTDeadlinesAndCancellationPropagate() async throws {
        let d = try ImageDescriptor.greyscale16(width: 64, height: 64, meaningfulBits: 12)
        let source = try ImageDestination.allocate(descriptor: d).writeUInt16 { x, y in UInt16((x * 71 + y * 193) & 4095) }
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy))
        let tiny = try ResourceLimits(deadlineSeconds: 0.000001)
        do {
            _ = try await encoder.encode(source, options: .init(resourceLimits: tiny))
            Issue.record("Deadline was ignored")
        } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        let task = Task { try await encoder.encode(source) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation was ignored") }
        catch is CancellationError { }
    }

}
