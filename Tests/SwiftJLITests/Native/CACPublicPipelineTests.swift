// SPDX-License-Identifier: MIT
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
    // Keep the TaskLocal binding and temporary C metadata in a synchronous
    // frame. The Intel Release CI failure reports a non-LIFO task allocation
    // cleanup when this scope is inlined into the async parameterised test.
    // This boundary is a candidate compiler workaround; its assertions and
    // the asynchronous public decode coverage below remain unchanged.
    @inline(never)
    private static func requireAcceleratedEntropyKernel(
        dcTable: HuffmanTable, acTable: HuffmanTable, lookup: ACLookahead
    ) throws {
        try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 2)) {
            #expect(NativeOperation.workerLimit >= 2)
            try CDCTKernel.withBorrowed(dcTable: dcTable, acTable: acTable, lookup: lookup,
                enabled: NativeOperation.current?.backend == .accelerated) { kernel in
                _ = try #require(kernel)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.activeProcessorCount >= 2
        && SwiftJLI.Decoder.capabilities.availableBackends.contains(.accelerated)),
        arguments: [8, 12], [(false, 255), (true, 255), (false, 256), (true, 256),
                            (false, 257), (true, 257), (false, 1023), (true, 1023)])
    func publicDecodePreservesRestartCrossingAndCallerPadding(precision: Int, modes: (Bool, Int)) async throws {
        let (floating, restart) = modes
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
        let bytes = try JLIEncoder().encode(source, configuration: .init(quality: 87, restartInterval: restart))
        var parser = MarkerReader(data: bytes)
        let parsed = try parser.parse()
        #expect(parsed.frameInfo.precision == precision && parsed.restartInterval == restart)
        let scan = try #require(parsed.scans.first)
        let selector = try #require(scan.header.components.first)
        let dcTable = try #require(scan.dcTables[selector.dcTableId])
        let table = try #require(scan.acTables[selector.acTableId])
        let nativeConfiguration = JLIDecoderConfiguration(outputPixelFormat: floating ? .float32 : nil)
        let acceleratedPlan = try #require(try SequentialGreyscalePlan.make(parsed: parsed,
            configuration: nativeConfiguration, hasDestination: true, normaliseXYBOutput: false,
            workerLimit: 2, backend: .accelerated))
        // 65 * 33 blocks reuse both slots and leave a 97-block final batch.
        // Restarts immediately before/at/after 256 exercise the FMA boundary;
        // 1023 retains the original GEMM boundary and crosses four FMA batches.
        #expect(acceleratedPlan.pipelined && acceleratedPlan.blockCount == 2145)
        let batchBlocks = BlockLocalIDCT.available ? 256 : 1024
        #expect(acceleratedPlan.batchBlocks == batchBlocks && !acceleratedPlan.dcOnlyTable)
        #expect(acceleratedPlan.workspaceBytes == (BlockLocalIDCT.available ? 131_072 : 786_432))
        let referencePlan = try #require(try SequentialGreyscalePlan.make(parsed: parsed,
            configuration: nativeConfiguration, hasDestination: true, normaliseXYBOutput: false,
            workerLimit: 1, backend: .accelerated))
        #expect(!referencePlan.pipelined && referencePlan.batchBlocks == batchBlocks)
        let lookup = try #require(ACLookahead(table: table, blockCount: acceleratedPlan.blockCount))
        // Reproduce both accelerated C dispatch conditions in one synchronous
        // scope before either public async decode.
        try Self.requireAcceleratedEntropyKernel(dcTable: dcTable, acTable: table, lookup: lookup)

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
