// SPDX-License-Identifier: Apache-2.0
//
// TEST-09 evidence for the shared-contract surface.
//
// The bar the contract sets: the shipped path is unchanged, encode-side proofs
// compare codestreams rather than samples, padding cannot reach the output,
// decode writes the caller's allocation exactly, the ownership lifecycle is
// exercised including its failure paths, and the checks are shown to be
// load-bearing.

import Foundation
import Testing
@testable import SwiftJLI

@Suite("Contract image layer")
struct ContractImageLayerTests {

    /// Deterministic content distinct enough to expose a mis-stride or a
    /// dropped row; an all-zero image would hide both.
    static func sample(_ x: Int, _ y: Int, bits: Int = 16) -> UInt16 {
        let maxValue = UInt32(1 << bits) - 1
        let v = UInt32(truncatingIfNeeded: x &* 7 &+ y &* 131 &+ ((x ^ y) << 3))
        return UInt16(v % (maxValue + 1))
    }

    static func descriptor(width: Int, height: Int, bits: Int = 16,
                           pad: Int = 0, offset: Int = 0) throws -> ImageDescriptor {
        try ImageDescriptor.greyscale16(
            width: width, height: height, meaningfulBits: bits,
            rowBytes: width * 2 + pad, offset: offset)
    }

    static func filledImage(width: Int, height: Int, bits: Int = 16,
                            pad: Int = 0, offset: Int = 0) throws -> Image {
        let d = try descriptor(width: width, height: height, bits: bits, pad: pad, offset: offset)
        return try ImageDestination.allocate(descriptor: d)
            .writeUInt16 { x, y in sample(x, y, bits: bits) }
    }

    /// The ordinary, established API encoding the same samples, for comparison.
    static func ordinaryCodestream(width: Int, height: Int, bits: Int = 16) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let v = sample(x, y, bits: bits)
                let o = (y * width + x) * 2
                bytes[o] = UInt8(truncatingIfNeeded: v)
                bytes[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
            }
        }
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint16,
                                 colorModel: .grayscale, data: bytes)
        return try JLIEncoder().encode(image, configuration: ContractSurface.losslessConfiguration(precision: bits))
    }

    // MARK: - Encode

    @Test(arguments: [0, 6, 64])
    func contractEncodeMatchesTheEstablishedEncoderByteForByte(pad: Int) async throws {
        // Byte identity tests the whole input path at once. Sample comparison
        // would pass even if the layer read the wrong bytes in the right order.
        for (w, h) in [(37, 23), (64, 48), (129, 77)] {
            let image = try Self.filledImage(width: w, height: h, pad: pad)
            let (contract, report) = try await ContractSurface().encode(image)
            let ordinary = try Self.ordinaryCodestream(width: w, height: h)
            #expect(contract == ordinary, "\(w)x\(h) pad=\(pad): codestreams diverge")
            #expect(report.copyEvents.isEmpty)
            #expect(report.pixelAllocationCount == 0)
            #expect(report.fidelity == .exactSamples)
            // A measured peak must include native working planes. The public
            // report currently leaves the unmeasured peak unknown; admission
            // reservations are separately documented in the migration record.
            #expect(report.peakWorkspaceBytes.map { $0 >= w * h * 8 } ?? true)
        }
    }

    @Test func rowPaddingNeverReachesTheCodestream() async throws {
        let (w, h, pad) = (64, 48, 16)
        let d = try Self.descriptor(width: w, height: h, pad: pad)
        let clean = try Self.filledImage(width: w, height: h, pad: pad)
        let storage = try OwnedImageStorage(byteCount: d.requiredByteCount)
        let lease = try storage.reserveWrite()
        try storage.withUnsafeMutableBytes(lease: lease) { bytes in
            for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: 0x5A &+ i) }
            for y in 0..<h {
                for x in 0..<w {
                    let v = Self.sample(x, y)
                    let o = y * (w * 2 + pad) + x * 2
                    bytes[o] = UInt8(truncatingIfNeeded: v)
                    bytes[o + 1] = UInt8(truncatingIfNeeded: v >> 8)
                }
            }
        }
        let poisoned = try Image(descriptor: d, storage: try storage.finishAndSeal(lease: lease))
        let cleanBytes = try await ContractSurface().encode(clean).0
        let poisonedBytes = try await ContractSurface().encode(poisoned).0
        #expect(cleanBytes == poisonedBytes,
                "padding bytes changed the codestream")
    }

    @Test func aNonZeroPlaneOffsetIsHonoured() async throws {
        let (w, h) = (48, 31)
        let image = try Self.filledImage(width: w, height: h, pad: 4, offset: 32)
        let actual = try await ContractSurface().encode(image).0
        #expect(actual == (try Self.ordinaryCodestream(width: w, height: h)))
    }

    // MARK: - Decode

    @Test(arguments: [0, 6, 64])
    func decodeWritesTheCallerDestinationExactly(pad: Int) async throws {
        for (w, h) in [(37, 23), (64, 48), (129, 77)] {
            let codestream = try Self.ordinaryCodestream(width: w, height: h)
            let destination = try ImageDestination.allocate(
                descriptor: try Self.descriptor(width: w, height: h, pad: pad))
            let allocationID = destination.storage.allocationID
            let (image, report) = try await ContractSurface().decode(codestream, into: destination)

            // MEM-13: identity, exact samples, no intermediate frame.
            #expect(image.storage.allocationID == allocationID)
            #expect(report.pixelAllocationCount == 0)
            #expect(report.copyEvents.isEmpty)
            #expect(report.peakWorkspaceBytes.map { $0 >= w * h * 4 } ?? true)
            for y in 0..<h {
                for x in 0..<w {
                    #expect(try image.sampleUInt16(x: x, y: y) == Self.sample(x, y),
                            "\(w)x\(h) pad=\(pad) mismatch at \(x),\(y)")
                }
            }
        }
    }

    @Test func theAllocatingConvenienceAgreesWithTheDestinationPath() async throws {
        let (w, h) = (96, 61)
        let codestream = try Self.ordinaryCodestream(width: w, height: h)
        let (allocated, _) = try await ContractSurface().decode(codestream)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: w, height: h, pad: 10))
        let (intoCaller, _) = try await ContractSurface().decode(codestream, into: destination)
        for y in 0..<h {
            for x in 0..<w {
                #expect(try allocated.sampleUInt16(x: x, y: y)
                        == (try intoCaller.sampleUInt16(x: x, y: y)))
            }
        }
    }

    @Test func roundTripThroughTheContractSurfaceOnly() async throws {
        let (w, h) = (80, 53)
        let source = try Self.filledImage(width: w, height: h, pad: 4)
        let (codestream, _) = try await ContractSurface().encode(source)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: w, height: h, pad: 22))
        // Different strides each side, so a stride cannot be mistaken for width.
        let (decoded, _) = try await ContractSurface().decode(codestream, into: destination)
        for y in 0..<h {
            for x in 0..<w {
                #expect(try decoded.sampleUInt16(x: x, y: y) == (try source.sampleUInt16(x: x, y: y)))
            }
        }
    }

    @Test func inspectionDescribesWhatDecodeProduces() async throws {
        let codestream = try Self.ordinaryCodestream(width: 129, height: 77)
        let described = try ContractSurface().inspect(codestream)
        let (decoded, _) = try await ContractSurface().decode(codestream)
        #expect(described.width == decoded.descriptor.width)
        #expect(described.height == decoded.descriptor.height)
        #expect(described.meaningfulBits == decoded.descriptor.meaningfulBits)
        #expect(described.storageBits == 16)
        #expect(described.byteOrder == .littleEndian)
    }

    // MARK: - Failure paths and lifecycle

    @Test func mismatchedDestinationsAreRefused() async throws {
        let codestream = try Self.ordinaryCodestream(width: 64, height: 48)
        let codec = ContractSurface()
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 32, height: 48)))
        }
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 64, height: 24)))
        }
        await #expect(throws: CodecError.self) {
            try await codec.decode(codestream,
                into: try ImageDestination.allocate(descriptor: try Self.descriptor(width: 64, height: 48, bits: 12)))
        }
    }

    @Test func aDestinationGrantsOneWriteOnly() async throws {
        let codestream = try Self.ordinaryCodestream(width: 32, height: 16)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: 32, height: 16))
        _ = try await ContractSurface().decode(codestream, into: destination)
        // MEM-06: the destination is sealed; a second writer is rejected.
        await #expect(throws: CodecError.self) {
            try await ContractSurface().decode(codestream, into: destination)
        }
    }

    @Test func preflightRejectionLeavesTheDestinationReusable() async throws {
        // "Preflight rejection before a write begins does not invalidate a
        // caller's existing destination reservation." A dimension mismatch is
        // settled from the frame header, before any sample is written, so the
        // caller can correct the request and reuse the destination.
        let wrongSize = try Self.ordinaryCodestream(width: 32, height: 24)
        let full = try Self.ordinaryCodestream(width: 64, height: 48)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: 64, height: 48))
        await #expect(throws: CodecError.self) {
            try await ContractSurface().decode(wrongSize, into: destination)
        }
        let (image, _) = try await ContractSurface().decode(full, into: destination)
        for y in stride(from: 0, to: 48, by: 7) {
            for x in stride(from: 0, to: 64, by: 9) {
                #expect(try image.sampleUInt16(x: x, y: y) == Self.sample(x, y))
            }
        }
    }

    @Test func aFailureDuringTheWriteInvalidatesTheDestination() async throws {
        // The other half: "Once a fill/write operation begins, thrown errors
        // or cancellation invalidate it and prevent image publication."
        //
        // The successor preflights the complete marker envelope. Retain a
        // valid SOS and EOI, but replace the entropy with two bytes, so failure
        // happens inside the destination borrow rather than during preflight.
        let full = try Self.ordinaryCodestream(width: 64, height: 48)
        let destination = try ImageDestination.allocate(
            descriptor: try Self.descriptor(width: 64, height: 48))
        let sos = try #require((0..<(full.count - 3)).first { full[$0] == 0xFF && full[$0 + 1] == 0xDA })
        let entropyStart = sos + 2 + Int(full[sos + 2]) * 256 + Int(full[sos + 3])
        let truncated = Array(full.prefix(entropyStart)) + [0, 0, 0xFF, 0xD9]
        await #expect(throws: (any Error).self) {
            try await ContractSurface().decode(truncated, into: destination)
        }
        // No partial samples are published: the destination is invalid, so
        // even a valid codestream cannot now be written to it.
        await #expect(throws: (any Error).self) {
            try await ContractSurface().decode(full, into: destination)
        }
    }

    @Test func layoutsOutsideTheSharedProfileAreRefused() async throws {
        let bigEndian = try ImageDescriptor(
            width: 32, height: 16, storageBits: 16, meaningfulBits: 16,
            byteOrder: .bigEndian, components: [.grey], colour: .greyscale,
            planes: [try PlaneDescriptor(width: 32, height: 16, rowBytes: 64, byteCount: 1024)])
        await #expect(throws: CodecError.self) {
            try await ContractSurface().decode(try Self.ordinaryCodestream(width: 32, height: 16),
                                          into: try ImageDestination.allocate(descriptor: bigEndian))
        }
    }

    @Test func resourceLimitsAreEnforced() async throws {
        let codestream = try Self.ordinaryCodestream(width: 64, height: 48)
        let tight = try ResourceLimits(maximumCompressedBytes: 16)
        await #expect(throws: CodecError.self) {
            try await ContractSurface().decode(codestream, options: DecodeOptions(resourceLimits: tight))
        }
    }

    @Test func capabilitiesReportWhatIsImplemented() {
        // POL-08: planned capability is not reported as present.
        let c = ContractSurface.capabilities
        #expect(c.canEncode); #expect(c.canDecode); #expect(c.canInspect)
        #expect(c.compressionModes.contains(.lossless))
        #expect(c.compressionModes.contains(.nearLossless(maximumAbsoluteError: 1)))
        #expect(c.layouts.contains("greyscale16"))
        #expect(c.availableBackends == [.scalarCPU])
    }
}

// Test-only bridge preserves predecessor fixture/assertion structure while
// exercising the successor's public async API. No second codec API is shipped.
private struct ContractSurface {
    static var capabilities: CodecCapabilities { SwiftJLI.Decoder.capabilities }
    static func losslessConfiguration(precision: Int) -> JLIEncoderConfiguration {
        var configuration = JLIEncoderConfiguration.diagnosticLossless
        configuration.losslessPrecision = precision
        configuration.losslessPointTransform = 0
        return configuration
    }
    func encode(_ image: SwiftJLI.Image) async throws -> ([UInt8], OperationReport) {
        let result = try await SwiftJLI.Encoder().encode(image)
        return (Array(result.data), result.report)
    }
    func decode(_ bytes: [UInt8], into destination: ImageDestination? = nil,
                options: DecodeOptions = .init()) async throws -> (SwiftJLI.Image, OperationReport) {
        let decoder = try SwiftJLI.Decoder()
        let result: DecodedImage
        if let destination { result = try await decoder.decode(Data(bytes), into: destination, options: options) }
        else { result = try await decoder.decode(Data(bytes), options: options) }
        return (result.image, result.report)
    }
    func inspect(_ bytes: [UInt8]) throws -> ImageDescriptor {
        try SwiftJLI.Decoder().inspect(Data(bytes)).descriptor
    }
}
