// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class WorkspaceObservedStorage: WritableImageStorage {
    let owner: OwnedImageStorage
    let writes = Mutex(0)
    init(byteCount: Int) throws { owner = try OwnedImageStorage(byteCount: byteCount) }
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
                                  _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        writes.withLock { $0 += 1 }
        return try owner.withUnsafeMutableBytes(lease: lease) { bytes in
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

private func expectWorkspaceDenial(_ body: () throws -> Void) {
    do { try body(); Issue.record("Expected a resource-limit rejection before output was borrowed") }
    catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
    catch { Issue.record("Unexpected resource-limit error: \(error)") }
}

@Suite struct StreamingWorkspaceAdmissionTests {
    private static func jpeg(width: Int = 65, height: Int = 57,
                             precision: Int = 8, progressive: Bool = false,
                             colour: Bool = false) throws -> Data {
        let bps = precision == 8 ? 1 : 2, components = colour ? 3 : 1
        var bytes = [UInt8](repeating: 0, count: width * height * components * bps)
        for i in 0..<(width * height * components) {
            let value = (i * 151 + i / width * 17 + 117) & ((1 << precision) - 1)
            bytes[i * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { bytes[i * bps + 1] = UInt8(value >> 8) }
        }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: precision == 8 ? .uint8 : .uint16,
            colorModel: colour ? .rgb : .grayscale, data: bytes)
        return Data(try JLIEncoder().encode(image, configuration: .init(quality: 87, progressive: progressive)))
    }

    @Test(arguments: [8, 12], [false, true])
    func exactBudgetsIncludePaddingAndDenyBeforeOutputBorrow(precision: Int, floating: Bool) throws {
        let data = try Self.jpeg(precision: precision)
        let parsed = try JPEGCodec.parse(data, options: .init())
        let width = 65, height = 57, bps = floating ? 4 : precision == 8 ? 1 : 2
        let configuration = DecoderConfiguration(sampleFormat: floating ? .float32RawSamples : .nativeInteger)
        let native = JLIDecoderConfiguration(outputPixelFormat: floating ? .float32 : nil)
        // 9 x 8 padded blocks; shared coefficient/output and one scratch batch.
        // This boundary deliberately includes block padding, not width*height.
        let workspace = data.count * 64 + 36_864 + 1_048_576
        let offset = bps * 2, rowBytes = (width + 3) * bps
        let planeCapacity = offset + rowBytes * height, storageCapacity = planeCapacity + 11
        let plane = try PlaneDescriptor(width: width, height: height, offset: offset,
            sampleStride: bps, pixelStride: bps, rowBytes: rowBytes, byteCount: planeCapacity)
        let descriptor = try ImageDescriptor(width: width, height: height,
            sampleType: floating ? .floatingPoint : .unsignedInteger,
            storageBits: bps * 8, meaningfulBits: floating ? 32 : precision, planes: [plane])
        let total = workspace + storageCapacity + data.count

        for backend in Decoder.capabilities.availableBackends { for workers in [1, 8] {
            let expected = try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                // No borrowed destination: this remains the retained full-plane reference.
                try JLIDecoder().decodeParsed(parsed, configuration: native).data
            }
            let storage = try WorkspaceObservedStorage(byteCount: storageCapacity)
            let destination = try ImageDestination(descriptor: descriptor, storage: storage)
            let deniedLimits = [
                try ResourceLimits(maximumCompressedBytes: data.count, maximumDecodedBytes: storageCapacity,
                    maximumWorkspaceBytes: workspace - 1, maximumWorkers: workers, maximumMemoryBytes: total),
                try ResourceLimits(maximumCompressedBytes: data.count, maximumDecodedBytes: storageCapacity,
                    maximumWorkspaceBytes: workspace, maximumWorkers: workers, maximumMemoryBytes: total - 1),
                try ResourceLimits(maximumCompressedBytes: data.count, maximumDecodedBytes: storageCapacity - 1,
                    maximumWorkspaceBytes: workspace, maximumWorkers: workers, maximumMemoryBytes: total),
                try ResourceLimits(maximumCompressedBytes: data.count - 1, maximumDecodedBytes: storageCapacity,
                    maximumWorkspaceBytes: workspace, maximumWorkers: workers, maximumMemoryBytes: total)
            ]
            for limits in deniedLimits {
                expectWorkspaceDenial {
                    _ = try JPEGCodec.decode(data, into: destination, configuration: configuration,
                        options: .init(resourceLimits: limits, executionPolicy: .required(backend)))
                }
                #expect(storage.writes.withLock { $0 } == 0)
            }
            // Admission failures leave the destination available for this exact-bound decode.
            let limits = try ResourceLimits(maximumCompressedBytes: data.count, maximumDecodedBytes: storageCapacity,
                maximumWorkspaceBytes: workspace, maximumWorkers: workers, maximumMemoryBytes: total)
            let result = try JPEGCodec.decode(data, into: destination, configuration: configuration,
                options: .init(resourceLimits: limits, executionPolicy: .required(backend)))
            #expect(storage.writes.withLock { $0 } == 1)
            #expect(result.image.storage.allocationID == storage.allocationID)
            #expect(result.report.pixelAllocationCount == 0 && result.report.copyEvents.isEmpty)
            #expect(result.report.peakWorkspaceBytes == nil) // Reservation is not measured telemetry.
            try result.image.storage.withUnsafeBytes { bytes in
                #expect(bytes.prefix(offset).allSatisfy { $0 == 0xA5 })
                for y in 0..<height {
                    let start = offset + y * rowBytes, active = width * bps
                    #expect(bytes[start..<(start + active)]
                        .elementsEqual(expected[(y * active)..<((y + 1) * active)]))
                    #expect(bytes[(start + active)..<(start + rowBytes)].allSatisfy { $0 == 0xA5 })
                }
                #expect(bytes[planeCapacity..<storageCapacity].allSatisfy { $0 == 0xA5 })
            }
            // Allocating decode uses the same budgeted final-output path.
            let packedCapacity = width * height * bps
            let allocatedLimits = try ResourceLimits(maximumCompressedBytes: data.count,
                maximumDecodedBytes: packedCapacity, maximumWorkspaceBytes: workspace,
                maximumWorkers: workers, maximumMemoryBytes: workspace + packedCapacity + data.count)
            let allocated = try JPEGCodec.decode(data, into: nil, configuration: configuration,
                options: .init(resourceLimits: allocatedLimits, executionPolicy: .required(backend)))
            #expect(allocated.report.pixelAllocationCount == 1)
            #expect(try allocated.image.storage.withUnsafeBytes { Array($0) } == expected)
        } }
    }

    @Test func nonStreamingOperationsRetainTheirFullReservations() throws {
        let profiles: [(Data, DecoderConfiguration, Int)] = [
            (try Self.jpeg(progressive: true), .init(), 1),
            (try Self.jpeg(), .init(scale: 2), 1),
            (try Self.jpeg(colour: true), .init(), 1),
            (Data(LosslessTests.ll16), .init(), 1),
            // Exactly 2049 blocks: automatic scalar reconstruction keeps full planes.
            (try Self.jpeg(width: 24, height: 5464), .init(), 8)
        ]
        for (data, configuration, workers) in profiles {
            let parsed = try JPEGCodec.parse(data, options: .init())
            let native = JLIDecoderConfiguration(scale: configuration.scale)
            #expect(try SequentialGreyscalePlan.make(parsed: parsed, configuration: native,
                hasDestination: true, normaliseXYBOutput: false,
                workerLimit: workers, backend: .scalarCPU) == nil)
            let info = try JPEGCodec.info(parsed, scale: configuration.scale, decodedOutput: true, options: .init())
            let storage = try WorkspaceObservedStorage(byteCount: info.descriptor.requiredByteCount)
            let destination = try ImageDestination(descriptor: info.descriptor, storage: storage)
            let frame = parsed.frameInfo
            let workspace = data.count * 64 + frame.width * frame.height * frame.components.count
                * (frame.isLossless ? 8 : 128) + 1_048_576
            expectWorkspaceDenial {
                _ = try JPEGCodec.decode(data, into: destination, configuration: configuration,
                    options: .init(resourceLimits: try ResourceLimits(maximumWorkspaceBytes: workspace - 1,
                        maximumWorkers: workers), executionPolicy: .scalarCPU))
            }
            #expect(storage.writes.withLock { $0 } == 0)
            _ = try JPEGCodec.decode(data, into: destination, configuration: configuration,
                options: .init(resourceLimits: try ResourceLimits(maximumWorkspaceBytes: workspace,
                    maximumWorkers: workers), executionPolicy: .scalarCPU))
            #expect(storage.writes.withLock { $0 } == 1)
        }
    }

    @Test func automaticThresholdAndCheckedGeometryCannotUnderstateWorkspace() throws {
        let parsed = try JPEGCodec.parse(Self.jpeg(), options: .init())
        func replacingGeometry(width: Int, height: Int) -> ParsedJPEG {
            let frame = parsed.frameInfo
            return ParsedJPEG(frameInfo: .init(precision: frame.precision, width: width, height: height,
                components: frame.components, isProgressive: false), quantTables: parsed.quantTables,
                huffmanDCTables: parsed.huffmanDCTables, huffmanACTables: parsed.huffmanACTables,
                scans: parsed.scans, restartInterval: parsed.restartInterval,
                iccProfile: parsed.iccProfile, exif: parsed.exif)
        }
        let thresholds: [(Backend, Int)] = [(.scalarCPU, 2048), (.accelerated, 4096)]
        for (backend, threshold) in thresholds {
            let atThreshold = replacingGeometry(width: 8, height: threshold * 8)
            let plan = try #require(try SequentialGreyscalePlan.make(parsed: atThreshold, configuration: .default,
                hasDestination: true, normaliseXYBOutput: false, workerLimit: 8, backend: backend))
            #expect(plan.blockCount == threshold && plan.batchBlocks == 1024 && plan.workspaceBytes == 524_288)
            let aboveThreshold = replacingGeometry(width: 8, height: (threshold + 1) * 8)
            #expect(try SequentialGreyscalePlan.make(parsed: aboveThreshold, configuration: .default,
                hasDestination: true, normaliseXYBOutput: false, workerLimit: 8, backend: backend) == nil)
            #expect(try SequentialGreyscalePlan.make(parsed: aboveThreshold, configuration: .default,
                hasDestination: true, normaliseXYBOutput: false, workerLimit: 1, backend: backend)?.workspaceBytes == 524_288)
            #expect(try SequentialGreyscalePlan.make(parsed: atThreshold, configuration: .default,
                hasDestination: false, normaliseXYBOutput: false, workerLimit: 1, backend: backend) == nil)
            #expect(try SequentialGreyscalePlan.make(parsed: atThreshold, configuration: .default,
                hasDestination: true, normaliseXYBOutput: true, workerLimit: 1, backend: backend) == nil)
            for dimensions in [(Int.max, 1), (Int.max - 7, Int.max - 7)] {
                #expect(throws: CodecError.self) {
                    try SequentialGreyscalePlan.make(parsed: replacingGeometry(width: dimensions.0, height: dimensions.1),
                        configuration: .default, hasDestination: true, normaliseXYBOutput: false,
                        workerLimit: 1, backend: backend)
                }
            }
        }
    }
}
