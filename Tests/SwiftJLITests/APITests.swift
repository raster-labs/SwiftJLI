// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
import SwiftJLI

@Test func publicOperationsEncodeDecodeAndAdvertiseRealCapabilities() async throws {
    let encoder = try SwiftJLI.Encoder()
    let decoder = try SwiftJLI.Decoder()
    #expect(encoder.configuration.mode == .lossless)
    #expect(encoder.capabilities.canEncode)
    #expect(decoder.capabilities.canDecode && decoder.capabilities.canInspect)
    #expect(encoder.capabilities.availableBackends == [.scalarCPU])
    let descriptor = try ImageDescriptor.greyscale16(width: 1, height: 1)
    let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 65535 }
    let encoded = try await encoder.encode(image)
    #expect(encoded.data.prefix(2) == Data([0xff, 0xd8]))
    let info = try decoder.inspect(encoded.data)
    #expect(info.descriptor.meaningfulBits == 16)
    let decoded = try await decoder.decode(encoded.data)
    #expect(try decoded.image.sampleUInt16(x: 0, y: 0) == 65535)
    let destination = try ImageDestination.allocate(descriptor: descriptor)
    let direct = try await decoder.decode(encoded.data, into: destination)
    #expect(direct.image.storage.allocationID == destination.storage.allocationID)
    #expect(direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty)
    #expect(try direct.image.sampleUInt16(x: 0, y: 0) == 65535)
    #expect(throws: CodecError.self) { try decoder.inspect(Data()) }
    let reserved = try ImageDestination.allocate(descriptor: descriptor)
    do {
        _ = try await decoder.decode(Data(), into: reserved)
        Issue.record("Empty input must fail before writing.")
    } catch let error as CodecError { #expect(error.category == .malformedInput) }
    let next = try reserved.writeUInt16 { _, _ in 123 }
    #expect(try next.sampleUInt16(x: 0, y: 0) == 123)
}

@Test func configurationsAndBackendRequestsRejectUnsupportedChoices() throws {
    #expect(throws: CodecError.self) { try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: 0)) }
    #expect(try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: 1)).mode == .nearLossless(maximumAbsoluteError: 1))
    #expect(try EncoderConfiguration(mode: .lossy).mode == .lossy)
    #expect(throws: CodecError.self) {
        try SwiftJLI.Decoder(configuration: .init(codecOptions: .init(predictor: 2)))
    }
    do {
        _ = try SwiftJLI.Decoder().inspect(Data(), options: .init(executionPolicy: .required(.accelerated)))
        Issue.record("Malformed input must be rejected before choosing a codec backend.")
    } catch let error as CodecError { #expect(error.category == .malformedInput) }
    let limits = try ResourceLimits(maximumCompressedBytes: 1)
    do {
        _ = try SwiftJLI.Decoder().inspect(Data([0, 1]), options: .init(resourceLimits: limits))
        Issue.record("Compressed input limit was ignored.")
    } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
}

@Test func safeSampleWriterRejectsOutOfRangeWithoutTruncating() throws {
    let descriptor = try ImageDescriptor.greyscale16(width: 1, height: 1, meaningfulBits: 12)
    let destination = try ImageDestination.allocate(descriptor: descriptor)
    #expect(throws: CodecError.self) { try destination.writeUInt16 { _, _ in 4096 } }
    #expect(throws: CodecError.self) { try destination.writeUInt16 { _, _ in 4095 } }
    let valid = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 4095 }
    #expect(try valid.sampleUInt16(x: 0, y: 0) == 4095)
    #expect(throws: CodecError.self) { try valid.sampleUInt16(x: -1, y: 0) }
    #expect(throws: CodecError.self) { try valid.sampleUInt16(x: 1, y: 0) }
}

@Test func cancellationDuringSyntheticRowsInvalidatesDestination() async throws {
    let descriptor = try ImageDescriptor.greyscale16(width: 3, height: 3)
    let provider = try OwnedImageStorage(byteCount: descriptor.requiredByteCount)
    let destination = try ImageDestination(descriptor: descriptor, storage: provider)
    let visits = Mutex(0)
    let cancelled = await Task {
        do {
            _ = try destination.writeUInt16 { x, y in
                visits.withLock { $0 += 1 }
                if x == 0 && y == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                return 29
            }
            return false
        } catch is CancellationError { return true }
        catch { return false }
    }.value
    #expect(cancelled)
    #expect(visits.withLock { $0 } == 3)
    #expect(throws: CodecError.self) { try provider.reserveWrite() }
    #expect(throws: CodecError.self) { try destination.writeUInt16 { _, _ in 0 } }
}

@Test func cancellationIsCheckedBeforeAllocatingStorage() async {
    let cancelled = await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        do {
            _ = try OwnedImageStorage(byteCount: 2)
            return false
        } catch is CancellationError { return true }
        catch { return false }
    }.value
    #expect(cancelled)
}

@Test func unknownMeasurementsStayUnknownAndMetadataIsBounded() throws {
    let report = OperationReport(backend: .scalarCPU, fidelity: .exactSamples)
    #expect(report.pixelAllocationCount == nil)
    #expect(report.peakPixelBytes == nil && report.peakWorkspaceBytes == nil)
    #expect(report.elapsedSeconds == nil)
    let descriptor = try ImageDescriptor.greyscale16(width: 1, height: 1)
    let source = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 0 }
    #expect(throws: CodecError.self) {
        try SwiftJLI.Image(descriptor: descriptor, storage: source.storage,
                          metadata: .init(entries: [:], requiredKeys: ["required"]))
    }
}

@Test func metadataAndDestinationLimitsUseCallerBudget() throws {
    let descriptor = try ImageDescriptor.greyscale16(width: 1, height: 1)
    let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 7 }
    let metadata = ImageMetadata(entries: ["a": Data([1, 2])])
    let adequate = try ResourceLimits(maximumDecodedBytes: 2, maximumMetadataBytes: 3, maximumMemoryBytes: 5)
    let accepted = try SwiftJLI.Image(descriptor: descriptor, storage: image.storage, metadata: metadata, limits: adequate)
    #expect(accepted.metadata == metadata)
    let shortMetadata = try ResourceLimits(maximumMetadataBytes: 2)
    #expect(throws: CodecError.self) {
        try SwiftJLI.Image(descriptor: descriptor, storage: image.storage, metadata: metadata, limits: shortMetadata)
    }
    let shortMemory = try ResourceLimits(maximumMemoryBytes: 4)
    #expect(throws: CodecError.self) {
        try SwiftJLI.Image(descriptor: descriptor, storage: image.storage, metadata: metadata, limits: shortMemory)
    }
    let tooSmall = try ResourceLimits(maximumDecodedBytes: 1)
    #expect(throws: CodecError.self) { try ImageDestination.allocate(descriptor: descriptor, limits: tooSmall) }
}

@Test func explicitLargerMetadataLimitIsHonoured() throws {
    let descriptor = try ImageDescriptor.greyscale16(width: 1, height: 1)
    let source = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 1 }
    let metadata = ImageMetadata(entries: ["a": Data(repeating: 0, count: ResourceLimits.default.maximumMetadataBytes)])
    #expect(throws: CodecError.self) {
        try SwiftJLI.Image(descriptor: descriptor, storage: source.storage, metadata: metadata)
    }
    let expanded = try ResourceLimits(maximumMetadataBytes: ResourceLimits.default.maximumMetadataBytes + 1)
    let image = try SwiftJLI.Image(descriptor: descriptor, storage: source.storage,
                                 metadata: metadata, limits: expanded)
    #expect(image.metadata.entries["a"]?.count == ResourceLimits.default.maximumMetadataBytes)
}

@Test func safeSampleAccessHonoursExplicitBigEndian() throws {
    let plane = try PlaneDescriptor(width: 1, height: 1, rowBytes: 2, byteCount: 2)
    let descriptor = try ImageDescriptor(width: 1, height: 1, byteOrder: .bigEndian, planes: [plane])
    let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 0xABCD }
    #expect(try image.sampleUInt16(x: 0, y: 0) == 0xABCD)
    #expect(try image.storage.withUnsafeBytes { Array($0) } == [0xAB, 0xCD])
}

@Test func decoderPreservesTaskCancellationError() async throws {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await SwiftJLI.Decoder().decode(Data())
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}
