// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class ParserObservedStorage: WritableImageStorage {
    private let owner: OwnedImageStorage
    let borrows = Mutex(0)
    init(byteCount: Int) throws { owner = try OwnedImageStorage(byteCount: byteCount) }
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeMutableBytes(lease: lease) { bytes in
            borrows.withLock { $0 += 1 }
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

private func expectParserError(_ category: CodecError.Category, _ body: () throws -> Void) {
    do { try body(); Issue.record("Expected parser admission failure") }
    catch let error as CodecError { #expect(error.category == category) }
    catch { Issue.record("Unexpected parser error: \(error)") }
}

@Suite struct ParserReservationTests {
    private static func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let length = payload.count + 2
        precondition(length <= 65535)
        return [255, marker, UInt8(length >> 8), UInt8(length & 255)] + payload
    }

    private static func table(_ id: UInt8 = 0, value: UInt8 = 0) -> [UInt8] {
        [id, 1] + Array(repeating: 0, count: 15) + [value]
    }

    private static func lossless(components: Int = 1, quantisers: Int = 0,
                                 metadata: [UInt8] = [], entropy: [UInt8] = [0]) -> Data {
        let ids = (0..<components).map { UInt8($0) }
        var bytes: [UInt8] = [255, 216]
        bytes += metadata
        bytes += segment(0xC3, [8, 0, 1, 0, 1, UInt8(components)] + ids.flatMap { [$0, 17, 0] })
        if quantisers > 0 {
            var definitions: [UInt8] = []
            for index in 0..<quantisers {
                definitions += [0] + Array(repeating: UInt8(index % 255 + 1), count: 64)
            }
            bytes += segment(0xDB, definitions)
        }
        bytes += segment(0xC4, table())
        bytes += segment(0xDA, [UInt8(components)] + ids.flatMap { [$0, 0] } + [1, 0, 0])
        bytes += entropy
        bytes += [255, 217]
        return Data(bytes)
    }

    @Test func bootstrapPrecedesStructuralReadsAndArrayCopyIsChargedSeparately() throws {
        let malformed = Data(repeating: 0, count: 17)
        let firstGate = 1_048_576 + malformed.count
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(malformed,
                limits: .init(maximumWorkspaceBytes: firstGate - 1))
        }
        expectParserError(.malformedInput) {
            _ = try JPEGEnvelope.validate(malformed,
                limits: .init(maximumWorkspaceBytes: firstGate))
        }
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(malformed,
                limits: .init(maximumWorkspaceBytes: firstGate,
                    maximumMemoryBytes: firstGate + malformed.count - 1))
        }
        expectParserError(.malformedInput) {
            _ = try JPEGEnvelope.validate(malformed,
                limits: .init(maximumWorkspaceBytes: firstGate,
                    maximumMemoryBytes: firstGate + malformed.count))
        }
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(malformed,
                limits: .init(maximumCompressedBytes: malformed.count - 1))
        }
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(Array(malformed),
                limits: .init(maximumWorkspaceBytes: firstGate))
        }
        expectParserError(.malformedInput) {
            _ = try JPEGEnvelope.validate(Array(malformed),
                limits: .init(maximumWorkspaceBytes: firstGate + malformed.count))
        }
    }

    @Test func invalidAndOverflowingReservationsThrowBeforeAnyAllocation() throws {
        for copies in [0, 3] {
            expectParserError(.resourceLimitExceeded) {
                _ = try JPEGParserReservation.bootstrap(compressedBytes: 1, inputCopies: copies)
            }
        }
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGParserReservation.bootstrap(compressedBytes: -1)
        }
        for copies in [1, 2] {
            #expect(throws: CodecError.self) {
                _ = try JPEGParserReservation.bootstrap(compressedBytes: Int.max, inputCopies: copies)
            }
        }
        for count in [-1, Int.max] {
            #expect(throws: CodecError.self) {
                _ = try JPEGParserReservation.workspace(compressedBytes: 0,
                    huffmanDefinitions: count, quantisationDefinitions: 0, scans: 0,
                    frameComponents: 0, scanComponents: 0, metadataBytes: 0)
            }
            #expect(throws: CodecError.self) {
                _ = try JPEGParserReservation.workspace(compressedBytes: 0,
                    huffmanDefinitions: 0, quantisationDefinitions: 0, scans: 0,
                    frameComponents: count, scanComponents: 1, metadataBytes: 0)
            }
            #expect(throws: CodecError.self) {
                _ = try JPEGParserReservation.workspace(compressedBytes: 0,
                    huffmanDefinitions: 0, quantisationDefinitions: 0, scans: 0,
                    frameComponents: 0, scanComponents: 0, metadataBytes: count)
            }
        }
    }

    @Test func exactParserAndDecodeLimitsRejectBeforeProviderEntryAndPermitReuse() throws {
        let data = Self.lossless()
        // One DC definition, one scan, one frame and one scan component.
        let parser = data.count + 1_048_576 + 4096 + 4096 + 128
        for limits in [
            try ResourceLimits(maximumWorkspaceBytes: parser - 1),
            try ResourceLimits(maximumWorkspaceBytes: parser, maximumMemoryBytes: parser + data.count - 1),
            try ResourceLimits(maximumCompressedBytes: data.count - 1)
        ] {
            expectParserError(.resourceLimitExceeded) {
                _ = try JPEGCodec.parse(data, options: .init(resourceLimits: limits))
            }
        }
        let exact = try ResourceLimits(maximumWorkspaceBytes: parser, maximumMemoryBytes: parser + data.count)
        let parsed = try JPEGCodec.parse(data, options: .init(resourceLimits: exact))
        #expect(parsed.parserWorkspaceBytes == parser)
        var native = MarkerReader(data: Array(data))
        #expect(try native.parse().parserWorkspaceBytes == 0)
        let plane = try PlaneDescriptor(width: 1, height: 1, sampleStride: 1, pixelStride: 1, rowBytes: 1, byteCount: 1)
        let descriptor = try ImageDescriptor(width: 1, height: 1, storageBits: 8, meaningfulBits: 8, planes: [plane])
        let storage = try ParserObservedStorage(byteCount: 1)
        let destination = try ImageDestination(descriptor: descriptor, storage: storage)
        let workspace = parser + 8, total = workspace + data.count + 1
        for limits in [
            try ResourceLimits(maximumWorkspaceBytes: parser - 1),
            try ResourceLimits(maximumWorkspaceBytes: workspace - 1),
            try ResourceLimits(maximumWorkspaceBytes: workspace, maximumMemoryBytes: total - 1)
        ] {
            expectParserError(.resourceLimitExceeded) {
                _ = try JPEGCodec.decode(data, into: destination, configuration: .init(),
                    options: .init(resourceLimits: limits))
            }
            #expect(storage.borrows.withLock { $0 } == 0)
        }
        let decoded = try JPEGCodec.decode(data, into: destination, configuration: .init(),
            options: .init(resourceLimits: try ResourceLimits(maximumWorkspaceBytes: workspace, maximumMemoryBytes: total)))
        #expect(storage.borrows.withLock { $0 } == 1)
        #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == [128])
        #expect(decoded.report.pixelAllocationCount == 0 && decoded.report.copyEvents.isEmpty)
        #expect(decoded.report.peakWorkspaceBytes == nil)
    }

    @Test func arrayCopyAllowanceTravelsWithTheRetainedParsedOwner() throws {
        let data = Self.lossless()
        let fromData = try JPEGEnvelope.validate(data, limits: .init())
        let fromArray = try JPEGEnvelope.validate(Array(data), limits: .init())
        #expect(fromArray.parserWorkspaceBytes == fromData.parserWorkspaceBytes + data.count)
        var reader = MarkerReader(validated: fromArray)
        let parsed = try reader.parse()
        #expect(parsed.parserWorkspaceBytes == fromArray.parserWorkspaceBytes)
        #expect(parsed.scans[0].entropyData.elementsEqual([0]))
    }

    @Test func everyProgressiveTableVersionAndScanSnapshotIsCounted() throws {
        var bytes: [UInt8] = [255, 216]
        bytes += Self.segment(0xC2, [8, 0, 1, 0, 1, 1, 0, 17, 0])
        bytes += Self.segment(0xDB, [0] + Array(repeating: 1, count: 64))
        for scan in 0..<128 {
            let definitions = [0, 1, 2, 3, 16, 17, 18, 19].flatMap {
                Self.table(UInt8($0), value: UInt8(scan % 2))
            }
            bytes += Self.segment(0xC4, definitions)
            bytes += Self.segment(0xDA, [1, 0, 0, 0, 0, 0]) + [0]
        }
        bytes += [255, 217]
        let data = Data(bytes)
        let expected = data.count + 1_048_576 + 1024 * 4096 + 1024 + 128 * 4096 + 129 * 64
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(data, limits: .init(maximumWorkspaceBytes: expected - 1))
        }
        let admitted = try JPEGEnvelope.validate(data, limits: .init(maximumWorkspaceBytes: expected))
        var reader = MarkerReader(validated: admitted)
        let parsed = try reader.parse()
        #expect(parsed.parserWorkspaceBytes == expected && parsed.scans.count == 128)
        for (index, scan) in parsed.scans.enumerated() {
            #expect(scan.dcTables.count == 4 && scan.acTables.count == 4)
            #expect(scan.dcTables[0]?.values == [UInt8(index % 2)])
            #expect(scan.acTables[3]?.values == [UInt8(index % 2)])
        }
        // The structural bound does not make this repeated initial-DC script a
        // valid progressive sequence; existing semantic validation still rejects.
        #expect(throws: CodecError.self) { try JPEGCodec.validateDCT(parsed) }
        bytes.removeLast(2)
        bytes += Self.segment(0xDA, [1, 0, 0, 0, 0, 0]) + [0, 255, 217]
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGEnvelope.validate(Data(bytes), limits: .init())
        }
    }

    @Test func repeatedQuantisersUseDefinitionCountNotFourFinalIDs() throws {
        let data = Self.lossless(quantisers: 1008)
        let expected = data.count + 1_048_576 + 4096 + 1008 * 1024 + 4096 + 128
        expectParserError(.resourceLimitExceeded) {
            _ = try JPEGCodec.parse(data, options: .init(resourceLimits: try .init(maximumWorkspaceBytes: expected - 1)))
        }
        let parsed = try JPEGCodec.parse(data,
            options: .init(resourceLimits: try .init(maximumWorkspaceBytes: expected)))
        #expect(parsed.parserWorkspaceBytes == expected && parsed.quantTables.count == 4)
        #expect(parsed.quantTables[0] == Array(repeating: 1007 % 255 + 1, count: 64))
        let bad = [UInt8](Self.lossless().prefix(2)) + Self.segment(0xDB, [0] + Array(repeating: 1, count: 63))
            + Array(Self.lossless().dropFirst(2))
        expectParserError(.malformedInput) { _ = try JPEGEnvelope.validate(Data(bad), limits: .init()) }
    }

    @Test func allComponentEntriesAreChargedBeforeUnsupportedProfileRejection() throws {
        let data = Self.lossless(components: 255)
        let expected = data.count + 1_048_576 + 4096 + 4096 + 510 * 64
        let parsed = try JPEGCodec.parse(data,
            options: .init(resourceLimits: try .init(maximumWorkspaceBytes: expected)))
        #expect(parsed.frameInfo.components.count == 255 && parsed.scans[0].header.components.count == 255)
        #expect(parsed.parserWorkspaceBytes == expected)
        expectParserError(.unsupportedFeature) {
            _ = try JPEGCodec.inspect(data, options: .init(resourceLimits: try .init(maximumWorkspaceBytes: expected)))
        }
    }

    @Test func maximumExifAndAllICCSequenceSlotsAreCountedAndReassembled() throws {
        let exif = Array(repeating: UInt8(37), count: 65527)
        var metadata = Self.segment(0xE0, [1, 2, 3])
        metadata += Self.segment(0xE1, [69, 120, 105, 102, 0, 0] + exif)
        let identifier = Array("ICC_PROFILE\0".utf8)
        for sequence in (1...255).reversed() {
            metadata += Self.segment(0xE2, identifier + [UInt8(sequence), 255, UInt8(sequence)])
        }
        let payloadBytes = 3 + 65533 + 255 * 15
        let data = Self.lossless(metadata: metadata)
        let expected = data.count + 1_048_576 + 4096 + 4096 + 128 + 4 * payloadBytes
        let limits = try ResourceLimits(maximumWorkspaceBytes: expected,
            maximumMetadataBytes: payloadBytes, maximumICCBytes: 255)
        let parsed = try JPEGCodec.parse(data, options: .init(resourceLimits: limits))
        #expect(parsed.parserWorkspaceBytes == expected && parsed.exif == exif)
        #expect(parsed.iccProfile == (1...255).map { UInt8($0) })
        let info = try JPEGCodec.inspect(data, options: .init(resourceLimits: limits))
        #expect(info.metadata.entries["Exif"] == Data(exif))
        for denied in [
            try ResourceLimits(maximumMetadataBytes: payloadBytes - 1),
            try ResourceLimits(maximumICCBytes: 254),
            try ResourceLimits(maximumWorkspaceBytes: expected - 1)
        ] {
            expectParserError(.resourceLimitExceeded) {
                _ = try JPEGCodec.parse(data, options: .init(resourceLimits: denied))
            }
        }
    }

    @Test func entropyTraversalStillPollsCancellationAndRejectsTruncatedExtents() throws {
        let data = Self.lossless(entropy: Array(repeating: 0, count: 128 * 1024))
        let polls = Mutex(0)
        #expect(throws: CancellationError.self) {
            try NativeOperation.withSynchronousCancellation({
                if polls.withLock({ $0 += 1; return $0 }) == 10 { throw CancellationError() }
            }) {
                try NativeOperation.$current.withValue(.init(seconds: 120)) {
                    _ = try JPEGEnvelope.validate(data, limits: .init())
                }
            }
        }
        #expect(polls.withLock { $0 } == 10)
        expectParserError(.malformedInput) {
            _ = try JPEGEnvelope.validate(Data(data.dropLast()), limits: .init())
        }
    }

    @Test func validNoisyInputUsesItsBoundedWorkspaceAndRetainsExactSamples() throws {
        let width = 513, height = 257, count = width * height
        var seed: UInt32 = 0x6B291A3F, bytes = [UInt8](repeating: 0, count: count * 2)
        for index in 0..<count {
            seed = seed &* 1664525 &+ 1013904223
            let sample = (seed >> 8) & 65535
            bytes[index * 2] = UInt8(truncatingIfNeeded: sample)
            bytes[index * 2 + 1] = UInt8(sample >> 8)
        }
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
        let data = try NativeOperation.$current.withValue(.init(seconds: 120, maximumWorkers: 1)) {
            Data(try JLIEncoder().encode(image, configuration: .init(lossless: true)))
        }
        let parsed = try JPEGCodec.parse(data, options: .init())
        let workspace = parsed.parserWorkspaceBytes + count * 8
        #expect(workspace < data.count * 64 + count * 8 + 1_048_576)
        let limits = try ResourceLimits(maximumWorkspaceBytes: workspace,
            maximumWorkers: 1, maximumMemoryBytes: workspace + data.count + bytes.count)
        let decoded = try JPEGCodec.decode(data, into: nil, configuration: .init(), options: .init(resourceLimits: limits))
        #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == bytes)
        #expect(decoded.report.fidelity == .exactSamples && decoded.report.pixelAllocationCount == 1)
        #expect(decoded.report.copyEvents.isEmpty && decoded.report.peakWorkspaceBytes == nil)
    }
}
