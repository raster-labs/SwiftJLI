// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

/// Initialises guard bytes inside the provider's existing synchronous borrow.
/// The owned provider retains all lease, sealing and invalidation enforcement.
private final class CACCanaryStorage: WritableImageStorage {
    private let owner: OwnedImageStorage
    init(byteCount: Int) throws { owner = try OwnedImageStorage(byteCount: byteCount) }
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeMutableBytes(lease: lease) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0xA5)
            return try body(bytes)
        }
    }
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage {
        try owner.finishAndSeal(lease: lease)
    }
    func abortAndInvalidate(lease: StorageWriteLease) throws {
        try owner.abortAndInvalidate(lease: lease)
    }
}

@Suite struct CACPublicPipelineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.activeProcessorCount >= 2), arguments: [8, 12], [false, true])
    func publicDecodePreservesRestartCrossingAndCallerPadding(precision: Int, floating: Bool) async throws {
        let width = 513, height = 257, sourceBps = precision == 8 ? 1 : 2
        let bps = floating ? 4 : sourceBps
        var samples = [UInt8](repeating: 0, count: width * height * sourceBps)
        for index in 0..<(width * height) {
            let value = (index * 151 + index / width * 17 + 117) & ((1 << precision) - 1)
            samples[index * sourceBps] = UInt8(truncatingIfNeeded: value)
            if sourceBps == 2 { samples[index * sourceBps + 1] = UInt8(value >> 8) }
        }
        let source = try JLIImage(width: width, height: height,
            pixelFormat: precision == 8 ? .uint8 : .uint16, colorModel: .grayscale, data: samples)
        let bytes = try JLIEncoder().encode(source, configuration: .init(quality: 87, restartInterval: 1023))
        var parser = MarkerReader(data: bytes)
        let parsed = try parser.parse()
        #expect(parsed.frameInfo.precision == precision && parsed.restartInterval == 1023)
        let scan = try #require(parsed.scans.first)
        let selector = try #require(scan.header.components.first)
        let dcTable = try #require(scan.dcTables[selector.dcTableId])
        let table = try #require(scan.acTables[selector.acTableId])
        let nativeConfiguration = JLIDecoderConfiguration(outputPixelFormat: floating ? .float32 : nil)
        let acceleratedPlan = try #require(try SequentialGreyscalePlan.make(parsed: parsed,
            configuration: nativeConfiguration, hasDestination: true, normaliseXYBOutput: false,
            workerLimit: 2, backend: .accelerated))
        // 65 * 33 blocks cover three alternating slots. Restarts at blocks
        // 1023 and 2046 straddle the canonical 1024-block batch boundaries.
        #expect(acceleratedPlan.pipelined && acceleratedPlan.blockCount == 2145)
        #expect(acceleratedPlan.batchBlocks == 1024 && !acceleratedPlan.dcOnlyTable)
        let referencePlan = try #require(try SequentialGreyscalePlan.make(parsed: parsed,
            configuration: nativeConfiguration, hasDestination: true, normaliseXYBOutput: false,
            workerLimit: 1, backend: .accelerated))
        #expect(!referencePlan.pipelined)
        let lookup = try #require(ACLookahead(table: table, blockCount: acceleratedPlan.blockCount))
        try CDCTKernel.withBorrowed(dcTable: dcTable, acTable: table, lookup: lookup, enabled: true) { kernel in
            _ = try #require(kernel)
        }

        let offset = 4, suffix = 8, rowBytes = width * bps + 12
        let capacity = offset + rowBytes * height + suffix
        let plane = try PlaneDescriptor(width: width, height: height, offset: offset,
            sampleStride: bps, pixelStride: bps, rowBytes: rowBytes, byteCount: capacity)
        let descriptor = try ImageDescriptor(width: width, height: height,
            sampleType: floating ? .floatingPoint : .unsignedInteger,
            storageBits: bps * 8, meaningfulBits: floating ? 32 : precision, planes: [plane])
        let decoder = try SwiftJLI.Decoder(configuration: .init(
            sampleFormat: floating ? .float32RawSamples : .nativeInteger)), data = Data(bytes)
        var backends: [Backend] = [.scalarCPU]
        #if canImport(Accelerate)
        backends.append(.accelerated)
        #endif
        for backend in backends {
            let reference = try await decoder.decode(data, options: .init(
                resourceLimits: .init(maximumWorkers: 1), executionPolicy: .required(backend)))
            let storage = try CACCanaryStorage(byteCount: capacity)
            let destination = try ImageDestination(descriptor: descriptor, storage: storage)
            let result = try await decoder.decode(data, into: destination, options: .init(
                resourceLimits: .init(maximumWorkers: 2), executionPolicy: .required(backend)))
            #expect(result.report.backend == backend && result.report.fallbackReason == nil)
            #expect(result.report.fidelity == reference.report.fidelity)
            #expect(result.report.pixelAllocationCount == 0 && result.report.copyEvents.isEmpty)
            #expect(result.image.storage.allocationID == storage.allocationID)
            #expect(result.image.descriptor == descriptor)
            try result.image.storage.withUnsafeBytes { actual in
                try reference.image.storage.withUnsafeBytes { expected in
                    #expect(actual.prefix(offset).allSatisfy { $0 == 0xA5 })
                    #expect(actual.suffix(suffix).allSatisfy { $0 == 0xA5 })
                    for row in 0..<height {
                        let first = offset + row * rowBytes, count = width * bps
                        // Compare raw bytes so Float32 equality includes every
                        // mantissa, exponent and sign bit, without a tolerance.
                        #expect(actual[first..<(first + count)]
                            .elementsEqual(expected[(row * count)..<((row + 1) * count)]))
                        #expect(actual[(first + count)..<(first + rowBytes)].allSatisfy { $0 == 0xA5 })
                    }
                }
            }
            // Both public destinations have completed their one-writer lifecycle.
            #expect(throws: CodecError.self) { try storage.reserveWrite() }
        }
    }
}
