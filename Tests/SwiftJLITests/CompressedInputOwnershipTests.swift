// SPDX-License-Identifier: Apache-2.0
import Dispatch
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class CompressedAllocationReleases: Sendable {
    let count = Mutex(0)
}

private func compressedAutoreleasePool<R>(_ body: () throws -> R) rethrows -> R {
    #if canImport(ObjectiveC)
    return try autoreleasepool(invoking: body)
    #else
    return try body()
    #endif
}

@Suite struct CompressedInputOwnershipTests {
    // Existing independently encoded fixture, plus an admitted APP0 segment.
    // This forces a large heap-backed compressed input without adding image work.
    private static func largeFixture() -> [UInt8] {
        let payloadCount = 60_000, segmentLength = payloadCount + 2
        return [255, 216, 255, 224, UInt8(segmentLength >> 8), UInt8(segmentLength & 255)]
            + [UInt8](repeating: 19, count: payloadCount) + Array(LosslessTests.ll16.dropFirst(2))
    }

    private static func parse(_ data: Data) throws -> ParsedJPEG {
        try JPEGCodec.parse(data, options: .init())
    }

    private static func retainedParsedInput(_ releases: CompressedAllocationReleases) throws
        -> (parsed: ParsedJPEG, sharesOriginalAllocation: Bool) {
        let bytes = largeFixture()
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: bytes.count, alignment: 16)
        bytes.withUnsafeBytes { source in
            if let base = source.baseAddress { pointer.copyMemory(from: base, byteCount: source.count) }
        }
        let data = Data(bytesNoCopy: pointer, count: bytes.count, deallocator: .custom { pointer, _ in
            pointer.deallocate()
            releases.count.withLock { $0 += 1 }
        })
        let parsed = try parse(data)
        let scan = try #require(parsed.scans.first)
        let originalStart = UInt(bitPattern: pointer)
        // A bridge may retain or copy the input. Record the actual representation
        // while both allocations are alive; the caller Data is not returned.
        let sharesOriginalAllocation = withExtendedLifetime(data) {
            let scanStart = scan.entropyData.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
            return (originalStart..<(originalStart + UInt(bytes.count))).contains(scanStart)
        }
        return (parsed, sharesOriginalAllocation)
    }

    @inline(never)
    private static func consumeAndDropParsedInput(_ releases: CompressedAllocationReleases,
                                                 previousReleases: Int) throws {
        let (parsed, sharesOriginalAllocation) = try retainedParsedInput(releases)
        let decoded = try JLIDecoder().decodeParsed(parsed)
        #expect(!decoded.data.isEmpty)
        withExtendedLifetime(parsed) {
            let expected = previousReleases + (sharesOriginalAllocation ? 0 : 1)
            #expect(releases.count.withLock { $0 } == expected)
        }
    }

    @Test func repeatedDecodesReleaseInputsWithoutAnOuterAutoreleasePool() throws {
        let releases = CompressedAllocationReleases()
        // A fresh large allocation per call catches NSData inner-pointer
        // autoreleases accumulating until an unrelated event-loop pool drains.
        // No outer pool may mask this test's ordinary function-scope release.
        for index in 0..<16 {
            try Self.consumeAndDropParsedInput(releases, previousReleases: index)
            #expect(releases.count.withLock { $0 } == index + 1)
        }
    }

    @Test(arguments: [0, 17])
    func largeDataScansShareOneOwnerWithRebasedIndices(origin: Int) throws {
        let jpeg = Self.largeFixture()
        let container = Data([UInt8](repeating: 0xA5, count: origin) + jpeg + [0xA5, 0xA5])
        let data = container[origin..<(origin + jpeg.count)]
        #expect(data.startIndex == origin)
        let envelope = try JPEGEnvelope.validate(data, limits: .init())
        let ownerAddress = envelope.bytes.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        #if canImport(ObjectiveC)
        // Apple bridge zero-copy is separately qualified. Other Foundation
        // implementations may copy while preserving all ownership semantics.
        let inputAddress = data.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        #expect(ownerAddress == inputAddress)
        #endif
        var parser = MarkerReader(validated: envelope)
        let parsed = try parser.parse()
        for (scan, range) in zip(parsed.scans, envelope.entropyRanges) {
            #expect(scan.entropyData.startIndex == 0 && scan.entropyData.count == range.count)
            let scanAddress = scan.entropyData.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
            #expect(scanAddress == ownerAddress + UInt(range.lowerBound))
            #expect(scan.entropyData.elementsEqual(jpeg[range]))
            // Ordinary Collection slices preserve indices; explicit scan views rebase.
            if scan.entropyData.count > 4 {
                #expect(scan.entropyData[2..<4].startIndex == 2)
                #expect(scan.entropyData.rebasedSlice(2..<4).startIndex == 0)
            }
        }
    }

    @Test func progressiveScansKeepSnapshotTablesAfterCallerMutationAndRelease() throws {
        var input = Data(ProgressiveTests.progressiveJPEG)
        let parsed = try Self.parse(input)
        let expected = try JLIDecoder().decode(from: ProgressiveTests.baselineJPEG).data
        #expect(parsed.scans.count > 1)
        let acSnapshots = parsed.scans.compactMap { $0.acTables[0].map { $0.bits + $0.values } }
        #expect(Set(acSnapshots).count > 1) // Fixture redefines AC table 0 between SOS markers.
        input.resetBytes(in: input.startIndex..<input.endIndex)
        input.removeAll(keepingCapacity: false)
        #expect(try JLIDecoder().decodeParsed(parsed).data == expected)
    }

    @Test func mutableFoundationInputCannotChangeTheRetainedSnapshot() throws {
        let mutable = NSMutableData(data: Data(LosslessRestartTests.cjpegRestart12))
        var input = Data(referencing: mutable)
        let parsed = try Self.parse(input)
        let expected = try JLIDecoder().decode(from: LosslessRestartTests.cjpegRestart12).data
        mutable.resetBytes(in: NSRange(location: 0, length: mutable.length))
        input.resetBytes(in: input.startIndex..<input.endIndex)
        input.removeAll(keepingCapacity: false)
        #expect(try JLIDecoder().decodeParsed(parsed).data == expected)
    }

    @Test func parsedScansPreserveBytesAndReleaseTheOriginalAllocationExactlyOnce() throws {
        let releases = CompressedAllocationReleases()
        try compressedAutoreleasePool {
            let (parsed, sharesOriginalAllocation) = try Self.retainedParsedInput(releases)
            let expectedWhileRetained = sharesOriginalAllocation ? 0 : 1
            #expect(releases.count.withLock { $0 } == expectedWhileRetained)
            let expected = try JLIDecoder().decode(from: LosslessTests.ll16).data
            #expect(try JLIDecoder().decodeParsed(parsed).data == expected)
            withExtendedLifetime(parsed) { #expect(releases.count.withLock { $0 } == expectedWhileRetained) }
        }
        #expect(releases.count.withLock { $0 } == 1)
    }

    @Test func cachedReadersStayInsideRebasedStuffedRestartAndTruncatedRanges() throws {
        let entropy: [UInt8] = [0x12, 0xFF, 0, 0x34, 0xFF, 0xD0, 0x56, 0x78]
        let owner = JPEGBytes(Data([0x99, 0x99, 0x99] + entropy + [UInt8](repeating: 0x42, count: 24)))
        let scan = owner.rebasedSlice(3..<(3 + entropy.count))
        #expect(try JPEGEntropyBoundary.find(in: scan, from: 0) == entropy.count)
        var reader = BitReader(data: scan)
        #expect(try reader.readBits(8) == 0x12)
        #expect(try reader.readBits(8) == 0xFF)
        #expect(try reader.readBits(8) == 0x34)
        try reader.skipRestartMarker(expectedIndex: 0)
        #expect(try reader.readBits(16) == 0x5678)
        #expect(throws: JLIError.self) { try reader.readBits(1) }
        var segment = BitReader(data: scan, startingAt: 6)
        #expect(try segment.readBits(16) == 0x5678)
        #expect(throws: JLIError.self) { try segment.readBits(1) }
        // The 0x00 exists in the owner but is outside this truncated scan.
        var truncated = BitReader(data: scan.rebasedSlice(0..<2))
        #expect(try truncated.readBits(8) == 0x12)
        #expect(throws: JLIError.self) { try truncated.readBits(8) }
        let plainOwner = JPEGBytes(Data(Array(UInt8(1)...UInt8(32))))
        var exactBulk = BitReader(data: plainOwner.rebasedSlice(5..<13))
        for value in [UInt32(0x0607), 0x0809, 0x0A0B, 0x0C0D] {
            #expect(try exactBulk.readBits(16) == value)
        }
        #expect(throws: JLIError.self) { try exactBulk.readBits(1) }
        var empty = BitReader(data: owner.rebasedSlice(3..<3))
        #expect(throws: JLIError.self) { try empty.readBits(1) }
    }

    @Test func joinedReadersShareOnlyTheOwnerAndReleaseAfterCompletion() throws {
        let releases = CompressedAllocationReleases()
        try compressedAutoreleasePool {
            let (parsed, sharesOriginalAllocation) = try Self.retainedParsedInput(releases)
            let expectedWhileRetained = sharesOriginalAllocation ? 0 : 1
            let expected = try JLIDecoder().decode(from: LosslessTests.ll16).data
            let results = Mutex<[Bool]>([])
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                do {
                    // decodeParsed constructs all pointer-bearing readers locally.
                    let actual = try JLIDecoder().decodeParsed(parsed).data
                    results.withLock { $0.append(actual == expected) }
                } catch {
                    results.withLock { $0.append(false) }
                }
            }
            #expect(results.withLock { $0.count == 8 && $0.allSatisfy { $0 } })
            withExtendedLifetime(parsed) { #expect(releases.count.withLock { $0 } == expectedWhileRetained) }
        }
        #expect(releases.count.withLock { $0 } == 1)
    }
}
