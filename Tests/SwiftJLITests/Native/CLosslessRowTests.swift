// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

/// Observes the existing owner's synchronous lease without adopting a pointer.
/// Copying only a small failure prefix proves partial row output preceded abort.
private final class CLosslessObservedStorage: WritableImageStorage {
    struct Observation: Sendable {
        var borrows = 0
        var aborts = 0
        var seals = 0
        var failurePrefix: [UInt8] = []
    }
    private let owner: OwnedImageStorage
    let observation = Mutex(Observation())
    init(byteCount: Int) throws { owner = try OwnedImageStorage(byteCount: byteCount) }
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeMutableBytes(lease: lease) { bytes in
            observation.withLock { $0.borrows += 1 }
            do { return try body(bytes) }
            catch {
                let prefix = Array(bytes.prefix(20))
                observation.withLock { $0.failurePrefix = prefix }
                throw error
            }
        }
    }
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage {
        let sealed = try owner.finishAndSeal(lease: lease)
        observation.withLock { $0.seals += 1 }
        return sealed
    }
    func abortAndInvalidate(lease: StorageWriteLease) throws {
        try owner.abortAndInvalidate(lease: lease)
        observation.withLock { $0.aborts += 1 }
    }
}

@Suite struct CLosslessRowTests {
    private func difference(_ table: HuffmanTable, _ reader: inout BitReader) throws -> Int32 {
        if let value = reader.fastDecodeLosslessDifference(table) { return value }
        let category = Int(try HuffmanDecoder.decodeSymbol(from: &reader, table: table))
        if category == 0 { return 0 }
        if category == 16 { return -32768 }
        return try HuffmanDecoder.decodeValue(from: &reader, category: category)
    }

    private func reference(_ reader: inout BitReader, table: HuffmanTable, count: Int,
        seed: Int32, into output: UnsafeMutableRawBufferPointer
    ) throws -> (first: Int32, last: Int32) {
        var first: Int32 = 0, value = seed
        for index in 0..<count {
            value = (value + (try difference(table, &reader))) & 0xFFFF
            if index == 0 { first = value }
            output[index * 2] = UInt8(truncatingIfNeeded: value)
            output[index * 2 + 1] = UInt8(value >> 8)
        }
        return (first, value)
    }

    /// Compare all partial bytes, next-read errors and physical/aligned cursors,
    /// not merely successful sample values. The destination begins at an odd byte.
    private func compare(_ bytes: [UInt8], skipping: Int = 0, table: HuffmanTable,
        kernel: CLosslessRowKernel, count: Int, seed: Int32 = 32768
    ) throws -> Bool {
        var referenceReader = BitReader(data: bytes), candidate = referenceReader
        _ = try referenceReader.readBits(skipping)
        _ = try candidate.readBits(skipping)
        var expected = [UInt8](repeating: 0xA5, count: count * 2 + 8), actual = expected
        let lhs = Result { try expected.withUnsafeMutableBytes { bytes in
            try reference(&referenceReader, table: table, count: count, seed: seed,
                into: .init(rebasing: bytes[3..<(3 + count * 2)]))
        } }
        let rhs = Result { try actual.withUnsafeMutableBytes { bytes in
            try candidate.decodeLeftUInt16Row(using: kernel, sampleCount: count, seed: seed,
                into: .init(rebasing: bytes[3..<(3 + count * 2)]))
        } }
        let failed: Bool
        switch (lhs, rhs) {
        case (.success(let a), .success(let b)):
            #expect(a.first == b.first && a.last == b.last)
            failed = false
        case (.failure(let a), .failure(let b)):
            #expect(String(describing: a) == String(describing: b))
            failed = true
        default:
            Issue.record("C lossless row changed completion/error boundary")
            failed = true
        }
        #expect(actual == expected)
        #expect(candidate.byteOffset == referenceReader.byteOffset)
        var alignedA = referenceReader, alignedB = candidate
        alignedA.alignToByte(); alignedB.alignToByte()
        #expect(alignedA.byteOffset == alignedB.byteOffset)
        let nextA = Result { try referenceReader.readBits(16) }
        let nextB = Result { try candidate.readBits(16) }
        switch (nextA, nextB) {
        case (.success(let a), .success(let b)): #expect(a == b)
        case (.failure(let a), .failure(let b)):
            #expect(String(describing: a) == String(describing: b))
        default: Issue.record("C lossless row changed remainder after completion/error")
        }
        #expect(candidate.byteOffset == referenceReader.byteOffset)
        return failed
    }

    private func emit(category: Int, magnitude: UInt32, table: HuffmanTable, writer: inout BitWriter) {
        let code = table.encodingTable[category]
        writer.writeBits(UInt32(code.code), count: Int(code.length))
        if category > 0 && category < 16 { writer.writeBits(magnitude, count: category) }
    }

    @Test func codeZeroExhaustsEveryPrefixOffsetAndCategoryBoundary() throws {
        var tables: [HuffmanTable] = []
        for category in 1...7 {
            tables.append(HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14),
                                       values: [UInt8(category), 16]))
            // A ninth-bit code is deliberately outside the specialised zero code. Its
            // invalid magnitude width must still fail at the original cursor.
            var lengths = [UInt8](repeating: 0, count: 16)
            lengths[0] = 1; lengths[1] = 1; lengths[8] = 1
            tables.append(HuffmanTable(bits: lengths, values: [UInt8(category), 16, 17]))
        }
        for invalid in [17, 31, 64, 255] {
            tables.append(HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14),
                                       values: [5, UInt8(invalid)]))
        }
        var successes = 0, failures = 0
        for table in tables {
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                #expect(kernel.usesCodeZero)
                for offset in 0..<8 { for prefix in 0..<256 {
                    var writer = BitWriter(estimatedMaxSize: 32)
                    writer.writeBits(0, count: offset)
                    writer.writeBits(UInt32(prefix), count: 8)
                    for tail: UInt32 in [0xA55A, 0x1234, 0xFF00, 0xD0FF] {
                        writer.writeBits(tail, count: 16)
                    }
                    writer.flush()
                    if try compare(writer.data, skipping: offset, table: table, kernel: kernel, count: 9) {
                        failures += 1
                    } else { successes += 1 }
                } }
            }
        }
        #expect(successes > 0 && failures > 0)
    }

    @Test func codeZeroTruncationStuffingAndMarkersMatchGenericAndSwift() throws {
        let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [5, 16])
        for allowCodeZero in [false, true] {
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true,
                                               allowCodeZero: allowCodeZero) { borrowed in
                let kernel = try #require(borrowed)
                #expect(kernel.usesCodeZero == allowCodeZero)
                for prefix in UInt16(0)...255 {
                    for tail: [UInt8] in [[], [0], [0xFF], [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
                                          Array(repeating: 0xA5, count: 16)] {
                        _ = try compare([UInt8(prefix)] + tail, table: table, kernel: kernel, count: 9)
                    }
                }
                var writer = BitWriter()
                for index in 0..<129 {
                    emit(category: index % 7 == 0 ? 16 : 5, magnitude: UInt32(index & 31),
                         table: table, writer: &writer)
                }
                writer.emitRestartMarker(7); writer.writeBits(0xA55A, count: 16); writer.flush()
                let bytes = writer.data
                for end in 0...bytes.count {
                    _ = try compare(Array(bytes.prefix(end)), table: table, kernel: kernel, count: 129)
                }
            }
        }
        // These valid short Huffman codes carry long magnitudes. No fixed-category
        // row is selected, so the original generic row stays in use.
        let longMagnitudes = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [15, 14])
        try CLosslessRowKernel.withBorrowed(table: longMagnitudes, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            #expect(!kernel.usesCodeZero)
        }
    }

    @Test func codeZeroFourSampleBoundariesPreservePredictorAndRemainder() throws {
        // Complete groups, one-to-three sample tails, and a longer row share
        // the unchanged Swift per-sample oracle, including its physical cursor.
        for category in 1...7 {
            let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14),
                                     values: [UInt8(category), 16])
            let threshold = UInt32(1 << (category - 1))
            let magnitudes: [UInt32] = [0, threshold - 1, threshold, (threshold << 1) - 1]
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                #expect(kernel.usesCodeZero)
                for count in [3, 4, 5, 7, 8, 9, 65] {
                    for offset in 0..<8 {
                        // A non-zero Huffman prefix in each candidate-group
                        // position must fall back without speculative consumption.
                        // Position four denotes an entirely specialised row.
                        for genericPosition in 0...4 {
                            var writer = BitWriter()
                            writer.writeBits(0, count: offset)
                            for index in 0..<count {
                                emit(category: genericPosition < 4 && index == genericPosition ? 16 : category,
                                     magnitude: magnitudes[index % 4], table: table, writer: &writer)
                            }
                            writer.emitRestartMarker(3)
                            writer.writeBits(0xA55A, count: 16)
                            writer.flush()
                            for seed: Int32 in [0, 65535] {
                                #expect(try !compare(writer.data, skipping: offset, table: table,
                                    kernel: kernel, count: count, seed: seed))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func codeZeroSelectionRequiresItsProvenWidthAndCodeLength() throws {
        for (length, category, expected): (Int, UInt8, Bool) in [
            (1, 0, false), (1, 1, true), (1, 7, true), (1, 8, false),
            (1, 15, false), (1, 16, false), (2, 5, false)] {
            var counts = [UInt8](repeating: 0, count: 16)
            counts[length - 1] = 1
            let table = HuffmanTable(bits: counts, values: [category])
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                #expect(kernel.usesCodeZero == expected)
            }
        }
    }

    @Test func everyCategoryOffsetSeedAndShortOrLongCodeMatchesSwift() throws {
        for length in [5, 9] {
            var bits = [UInt8](repeating: 0, count: 16); bits[length - 1] = 17
            let table = HuffmanTable(bits: bits, values: (0...16).map(UInt8.init))
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                for offset in 0..<8 { for seed: Int32 in [0, 2048, 32768, 65535] {
                    var writer = BitWriter()
                    writer.writeBits(0, count: offset)
                    for category in 0...16 {
                        let maximum = category > 0 && category < 16 ? UInt32((1 << category) - 1) : 0
                        for magnitude in [UInt32(0), maximum >> 1, (maximum >> 1) + 1, maximum] {
                            emit(category: category, magnitude: magnitude, table: table, writer: &writer)
                        }
                    }
                    writer.emitRestartMarker(5)
                    writer.writeBits(0xA55A, count: 16); writer.flush()
                    #expect(try !compare(writer.data, skipping: offset, table: table,
                        kernel: kernel, count: 68, seed: seed))
                    var reader = BitReader(data: writer.data)
                    _ = try reader.readBits(offset)
                    var output = [UInt8](repeating: 0, count: 136)
                    try output.withUnsafeMutableBytes {
                        _ = try reader.decodeLeftUInt16Row(using: kernel, sampleCount: 68, seed: seed, into: $0)
                    }
                    try reader.skipRestartMarker(expectedIndex: 5)
                    #expect(try reader.readBits(16) == 0xA55A)
                } }
            }
        }
    }

    @Test func truncationStuffingMarkersAndInvalidCategoriesPreservePartialRows() throws {
        let short = HuffmanTable(bits: [0, 0, 0, 0, 17] + Array(repeating: 0, count: 11),
                                 values: (0...16).map(UInt8.init))
        let long = HuffmanTable(bits: Array(repeating: 0, count: 8) + [17] + Array(repeating: 0, count: 7),
                                values: (0...16).map(UInt8.init))
        var successes = 0, failures = 0
        for table in [short, long] {
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                for byte in UInt16(0)...255 {
                    for tail: [UInt8] in [[], [0], [0xFF], [0xFF, 0], [0xFF, 0xD0], [0xFF, 0xD9],
                        Array(repeating: 0, count: 16), Array(repeating: 0xA5, count: 16),
                        [0, 1, 2, 3, 4, 5, 6, 0xFF, 0, 0xFF, 0xD7]] {
                        if try compare([UInt8(byte)] + tail, table: table, kernel: kernel, count: 9) {
                            failures += 1
                        } else { successes += 1 }
                    }
                }
                var writer = BitWriter()
                for index in 0..<68 {
                    let category = index % 17
                    emit(category: category, magnitude: UInt32(index * 311), table: table, writer: &writer)
                }
                writer.flush()
                let bytes = writer.data
                for end in 0...bytes.count {
                    _ = try compare(Array(bytes.prefix(end)), table: table, kernel: kernel, count: 68)
                }
            }
        }
        #expect(successes > 0 && failures > 0)
        // A malformed category consumes its symbol but no magnitude bits, even
        // when there are enough buffered bits for a tempting unchecked shift.
        for invalid in [17, 31, 32, 63, 64, 127, 255] { for length in [2, 9] {
            var bits = [UInt8](repeating: 0, count: 16); bits[length - 1] = 2
            let table = HuffmanTable(bits: bits, values: [1, UInt8(invalid)])
            try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
                let kernel = try #require(borrowed)
                for offset in 0..<8 {
                    var writer = BitWriter()
                    writer.writeBits(0, count: offset)
                    for _ in 0..<5 { emit(category: 1, magnitude: 1, table: table, writer: &writer) }
                    emit(category: invalid, magnitude: 0, table: table, writer: &writer)
                    writer.writeBits(0xA55A, count: 16); writer.flush()
                    #expect(try compare(writer.data, skipping: offset, table: table,
                        kernel: kernel, count: 9))
                }
            }
        } }
    }

    @Test func maximumWidthAndInvalidArgumentsRetainBufferBounds() throws {
        let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [1, 16])
        CLosslessRowKernel.withBorrowed(table: table, enabled: false) { #expect($0 == nil) }
        try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            var writer = BitWriter()
            for index in 0..<65535 {
                emit(category: index % 2 == 0 ? 16 : 1, magnitude: 1, table: table, writer: &writer)
            }
            writer.flush()
            #expect(try !compare(writer.data, table: table, kernel: kernel, count: 65535, seed: 65535))
            for (count, seed, capacity): (Int, Int32, Int) in [
                (0, 0, 4), (-1, 0, 4), (65536, 0, 4), (1, -1, 4), (1, 65536, 4), (3, 0, 5)] {
                var reader = BitReader(data: writer.data)
                var bytes = [UInt8](repeating: 0xA5, count: capacity)
                #expect(throws: JLIError.self) {
                    try bytes.withUnsafeMutableBytes {
                        _ = try reader.decodeLeftUInt16Row(using: kernel, sampleCount: count, seed: seed, into: $0)
                    }
                }
                #expect(reader.byteOffset == 0 && bytes.allSatisfy { $0 == 0xA5 })
            }
        }
    }

    @Test func rawDestinationMayAlreadyBeBoundToUInt16() throws {
        let table = HuffmanTable(bits: [1, 1] + Array(repeating: 0, count: 14), values: [1, 16])
        var writer = BitWriter()
        for _ in 0..<17 { emit(category: 1, magnitude: 1, table: table, writer: &writer) }
        writer.flush()
        var reader = BitReader(data: writer.data)
        var words = [UInt16](repeating: 0xA5A5, count: 22)
        var expected = [UInt8](repeating: 0xA5, count: words.count * 2)
        for index in 0..<17 {
            let value = 32769 + index
            expected[3 + index * 2] = UInt8(truncatingIfNeeded: value)
            expected[4 + index * 2] = UInt8(value >> 8)
        }
        try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { borrowed in
            let kernel = try #require(borrowed)
            try words.withUnsafeMutableBufferPointer { bound in
                let raw = UnsafeMutableRawBufferPointer(bound)
                let result = try reader.decodeLeftUInt16Row(using: kernel, sampleCount: 17,
                    seed: 32768, into: .init(rebasing: raw[3..<37]))
                #expect(result.first == 32769 && result.last == 32785)
            }
        }
        words.withUnsafeBytes { #expect($0.elementsEqual(expected)) }
    }

    static func fixture(precision: Int, restartRows: Int, malformedRange: Bool = false)
    throws -> (jpeg: [UInt8], expected: [UInt8], parsed: ParsedJPEG) {
        let width = 129, height = 129
        let lengths: [UInt8] = [1, 1] + Array(repeating: 0, count: 14)
        let table = HuffmanTable(bits: lengths, values: [1, 16])
        let half = Int32(1 << (precision - 1))
        var entropy = BitWriter(), expected: [UInt8] = [], previous = half
        for y in 0..<height {
            let segmentStart = y == 0 || (restartRows > 0 && y % restartRows == 0)
            if y > 0 && segmentStart { entropy.emitRestartMarker((y / restartRows - 1) & 7) }
            var value = segmentStart ? half : previous
            for x in 0..<width {
                let delta: Int32 = (precision == 16 || malformedRange) && (x + y) % 3 == 0
                    ? -32768 : ((x + y) % 2 == 0 ? 1 : -1)
                if delta == -32768 {
                    let code = table.encodingTable[16]
                    entropy.writeBits(UInt32(code.code), count: Int(code.length))
                } else { HuffmanEncoder.encodeDC(delta, table: table, writer: &entropy) }
                value = (value + delta) & 0xFFFF
                if x == 0 { previous = value }
                expected += [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]
            }
        }
        entropy.flush()
        var writer = MarkerWriter()
        writer.writeSOI()
        writer.writeSOF(progressive: false, precision: precision, width: width, height: height,
            components: [(1, 1, 1, 0)], lossless: true)
        writer.writeDHT(tables: [(0, 0, lengths, [1, 16])])
        if restartRows > 0 { writer.writeDRI(interval: width * restartRows) }
        writer.writeSOS(components: [(1, 0, 0)], spectralStart: 1, spectralEnd: 0)
        writer.writeEntropyData(entropy.data); writer.writeEOI()
        var parser = MarkerReader(data: writer.data)
        let parsed = try parser.parse()
        let parsedTable = try #require(parsed.scans.first?.dcTables[0])
        #expect(parsedTable.lookaheadLength[0] == 1 && parsedTable.lookaheadSymbol[0] == 1)
        #expect(LosslessLookahead(table: parsedTable, sampleCount: width * height) == nil)
        return (writer.data, expected, parsed)
    }

    @Test(arguments: [12, 16])
    func cAndSwiftRowsPreserveOddPaddingRestartsAndModulo(precision: Int) throws {
        for restartRows in [0, 1, 3] { for malformedRange in [false, true] {
            let fixture = try Self.fixture(precision: precision, restartRows: restartRows,
                                           malformedRange: malformedRange)
            var outputs: [[UInt8]] = []
            for useC in [false, true] {
                var bytes = [UInt8](repeating: 0xA5, count: 3 + 263 * 129 + 7)
                try bytes.withUnsafeMutableBytes { raw in
                    try NativeOperation.$current.withValue(.init(seconds: 60)) {
                        try JLIDecoder().decodeSharedLossless(fixture.parsed, into: .init(
                            bytes: .init(rebasing: raw[3..<(3 + 263 * 129)]),
                            rowBytes: 263, bytesPerSample: 2), useScalarCEntropy: useC)
                    }
                }
                for row in 0..<129 {
                    let first = 3 + row * 263
                    #expect(bytes[first..<(first + 258)].elementsEqual(fixture.expected[(row * 258)..<((row + 1) * 258)]))
                    #expect(bytes[(first + 258)..<(first + 263)].allSatisfy { $0 == 0xA5 })
                }
                #expect(bytes.prefix(3).allSatisfy { $0 == 0xA5 } && bytes.suffix(7).allSatisfy { $0 == 0xA5 })
                outputs.append(bytes)
            }
            #expect(outputs[0] == outputs[1])
        } }
    }

    @Test func rowCancellationStopsBeforeTheNextCLeaf() throws {
        let fixture = try Self.fixture(precision: 16, restartRows: 3)
        for useC in [false, true] {
            let polls = Mutex(0)
            var bytes = [UInt8](repeating: 0xA5, count: 129 * 129 * 2)
            #expect(throws: CancellationError.self) {
                try bytes.withUnsafeMutableBytes { raw in
                    try NativeOperation.withSynchronousCancellation({
                        if polls.withLock({ $0 += 1; return $0 }) == 4 { throw CancellationError() }
                    }) {
                        try NativeOperation.$current.withValue(.init(seconds: 60)) {
                            try JLIDecoder().decodeSharedLossless(fixture.parsed, into: .init(
                                bytes: raw, rowBytes: 258, bytesPerSample: 2), useScalarCEntropy: useC)
                        }
                    }
                }
            }
            #expect(bytes.prefix(516).elementsEqual(fixture.expected.prefix(516)))
            #expect(bytes.dropFirst(516).allSatisfy { $0 == 0xA5 })
        }
    }
}

@Suite struct CLosslessRowPublicTests {
    @Test func truncatedRowAbortsAfterWritingTheSamePrefixUnderBothPolicies() async throws {
        let lengths: [UInt8] = [1, 1] + Array(repeating: 0, count: 14)
        var entropy = BitWriter()
        // Both categories are admitted by the public parser. Five complete +1
        // samples precede an incomplete all-one code in the flush padding.
        // Unlike an invalid DHT category, this must reach destination.write.
        for _ in 0..<5 { entropy.writeBits(1, count: 2) }
        entropy.flush()
        var writer = MarkerWriter()
        writer.writeSOI()
        writer.writeSOF(progressive: false, precision: 16, width: 129, height: 129,
            components: [(1, 1, 1, 0)], lossless: true)
        writer.writeDHT(tables: [(0, 0, lengths, [1, 16])])
        writer.writeSOS(components: [(1, 0, 0)], spectralStart: 1, spectralEnd: 0)
        writer.writeEntropyData(entropy.data); writer.writeEOI()
        let decoder = try SwiftJLI.Decoder(), data = Data(writer.data)
        let descriptor = try ImageDescriptor.greyscale16(width: 129, height: 129)
        for policy: ExecutionPolicy in [.automatic, .required(.scalarCPU)] {
            let storage = try CLosslessObservedStorage(byteCount: descriptor.requiredByteCount)
            let destination = try ImageDestination(descriptor: descriptor, storage: storage)
            do {
                _ = try await decoder.decode(data, into: destination, options: .init(executionPolicy: policy))
                Issue.record("Truncated row unexpectedly decoded")
            } catch let error as CodecError {
                #expect(error.category == .malformedInput)
            }
            let observed = storage.observation.withLock { $0 }
            #expect(observed.borrows == 1 && observed.aborts == 1 && observed.seals == 0)
            #expect(observed.failurePrefix == [1, 128, 2, 128, 3, 128, 4, 128, 5, 128]
                + Array(repeating: UInt8(0), count: 10))
            #expect(throws: CodecError.self) { _ = try destination.write { _ in } }
            #expect(throws: CodecError.self) { try storage.reserveWrite() }
        }
    }

    @Test(arguments: [12, 16])
    func publicOwnedAndCallerDestinationsPreserveSamplesAndLifecycle(precision: Int) async throws {
        let fixture = try CLosslessRowTests.fixture(precision: precision, restartRows: 3)
        let decoder = try SwiftJLI.Decoder(), data = Data(fixture.jpeg)
        // Automatic opts into the portable C scalar leaf; explicit scalar
        // policies preserve Swift. Neither advertises an accelerated backend.
        for policy: ExecutionPolicy in [.automatic, .scalarCPU, .required(.scalarCPU)] {
            let options = DecodeOptions(executionPolicy: policy)
            let packed = try await decoder.decode(data, options: options)
            #expect(packed.report.backend == .scalarCPU && packed.report.fidelity == .exactSamples)
            #expect(packed.report.pixelAllocationCount == 1 && packed.report.copyEvents.isEmpty)
            try packed.image.storage.withUnsafeBytes { #expect($0.elementsEqual(fixture.expected)) }
            let rowBytes = 264, capacity = 2 + 129 * rowBytes + 6
            let plane = try PlaneDescriptor(width: 129, height: 129, offset: 2,
                sampleStride: 2, pixelStride: 2, rowBytes: rowBytes, byteCount: capacity)
            let descriptor = try ImageDescriptor(width: 129, height: 129,
                storageBits: 16, meaningfulBits: precision, planes: [plane])
            let storage = try OwnedImageStorage(byteCount: capacity)
            let destination = try ImageDestination(descriptor: descriptor, storage: storage)
            let decoded = try await decoder.decode(data, into: destination, options: options)
            #expect(decoded.report.backend == .scalarCPU && decoded.report.fallbackReason == nil)
            #expect(decoded.report.fidelity == .exactSamples)
            #expect(decoded.report.pixelAllocationCount == 0 && decoded.report.copyEvents.isEmpty)
            #expect(decoded.image.storage.allocationID == storage.allocationID)
            try decoded.image.storage.withUnsafeBytes { bytes in
                #expect(bytes.prefix(2).allSatisfy { $0 == 0 } && bytes.suffix(6).allSatisfy { $0 == 0 })
                for row in 0..<129 {
                    let first = 2 + row * rowBytes
                    #expect(bytes[first..<(first + 258)].elementsEqual(fixture.expected[(row * 258)..<((row + 1) * 258)]))
                    #expect(bytes[(first + 258)..<(first + rowBytes)].allSatisfy { $0 == 0 })
                }
            }
            #expect(throws: CodecError.self) { try storage.reserveWrite() }
        }
        await #expect(throws: CodecError.self) {
            _ = try await decoder.decode(data, options: .init(executionPolicy: .required(.accelerated)))
        }
    }
}
