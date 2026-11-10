// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct ValidatedEnvelopeTests {
    @Test func componentAndTableIDsRemainDistinctAtBitBoundaries() throws {
        func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] {
            let length = body.count + 2
            return [255, marker, UInt8(length >> 8), UInt8(length & 255)] + body
        }
        // Structural admission accepts distinct byte IDs before profile checks.
        // Exercise the complete ID domain, including zero and each 64-bit edge.
        let identifiers: [UInt8] = [0, 63, 64, 127, 128, 191, 192, 255]
        let tables: [[UInt8]] = [0, 1, 2, 3, 16, 17, 18, 19].map {
            [UInt8($0), 1] + [UInt8](repeating: 0, count: 15) + [0]
        }
        func jpeg(ids: [UInt8], definitions: [[UInt8]]) -> [UInt8] {
            let frame: [UInt8] = [8, 0, 1, 0, 1, UInt8(ids.count)]
                + ids.flatMap { [$0, 17, 0] }
            let scan: [UInt8] = [UInt8(ids.count)] + ids.flatMap { [$0, 0] } + [1, 0, 0]
            return [255, 216] + segment(195, frame)
                + segment(196, definitions.flatMap { $0 }) + segment(218, scan) + [0, 255, 217]
        }
        _ = try JPEGEnvelope.validate(jpeg(ids: identifiers, definitions: tables), limits: .init())
        for index in identifiers.indices.dropFirst() {
            var repeated = identifiers
            repeated[index] = identifiers[index - 1]
            #expect(throws: CodecError.self) {
                try JPEGEnvelope.validate(jpeg(ids: repeated, definitions: tables), limits: .init())
            }
        }
        for table in tables {
            #expect(throws: CodecError.self) {
                try JPEGEnvelope.validate(jpeg(ids: identifiers, definitions: tables + [table]), limits: .init())
            }
        }
    }

    @Test func reusedExtentsMatchIndependentMarkerTraversal() throws {
        // Existing independent cjpeg fixtures include stuffed bytes, restarts,
        // progressive scans and Huffman table redefinitions between scans.
        for bytes in [LosslessTests.llP1, LosslessTests.ll16,
                      LosslessRestartTests.cjpegRestart12,
                      ProgressiveTests.baselineJPEG, ProgressiveTests.progressiveJPEG] {
            let envelope = try JPEGEnvelope.validate(bytes, limits: .init())
            var validated = MarkerReader(validated: envelope)
            var reference = MarkerReader(data: bytes)
            let actual = try validated.parse(), expected = try reference.parse()
            #expect(actual.frameInfo.width == expected.frameInfo.width)
            #expect(actual.frameInfo.height == expected.frameInfo.height)
            #expect(actual.quantTables == expected.quantTables)
            #expect(actual.restartInterval == expected.restartInterval)
            #expect(actual.scans.count == expected.scans.count)
            #expect(envelope.entropyRanges.count == actual.scans.count)
            for index in actual.scans.indices {
                let a = actual.scans[index], b = expected.scans[index]
                #expect(a.entropyData == b.entropyData)
                #expect(a.entropyData.elementsEqual(bytes[envelope.entropyRanges[index]]))
                #expect(a.header.spectralStart == b.header.spectralStart)
                #expect(a.header.spectralEnd == b.header.spectralEnd)
                #expect(a.header.successiveApproxHigh == b.header.successiveApproxHigh)
                #expect(a.header.successiveApproxLow == b.header.successiveApproxLow)
                #expect(a.dcTables.keys.sorted() == b.dcTables.keys.sorted())
                #expect(a.acTables.keys.sorted() == b.acTables.keys.sorted())
                for key in b.dcTables.keys {
                    #expect(a.dcTables[key]?.bits == b.dcTables[key]?.bits)
                    #expect(a.dcTables[key]?.values == b.dcTables[key]?.values)
                }
                for key in b.acTables.keys {
                    #expect(a.acTables[key]?.bits == b.acTables[key]?.bits)
                    #expect(a.acTables[key]?.values == b.acTables[key]?.values)
                }
            }
        }
    }

    @Test func validatedInputOwnsAnImmutableSnapshot() throws {
        var bytes = LosslessRestartTests.cjpegRestart12
        let original = bytes
        let envelope = try JPEGEnvelope.validate(bytes, limits: .init())
        bytes.replaceSubrange(bytes.indices, with: [0, 1, 2])
        #expect(envelope.bytes.elementsEqual(original))
        var parser = MarkerReader(validated: envelope)
        let parsed = try parser.parse()
        #expect(parsed.frameInfo.width == 13 && parsed.frameInfo.height == 9)
        #expect(!parsed.scans[0].entropyData.isEmpty)
    }

    @Test func incompleteOrTrailingStreamsNeverProduceValidatedExtents() throws {
        let original = LosslessTests.ll16
        for bytes in [Array(original.dropLast()), Array(original.dropLast(2)),
                      original + [1], original + original, [255, 216, 255, 217]] {
            #expect(throws: CodecError.self) {
                try JPEGEnvelope.validate(bytes, limits: .init())
            }
        }
    }

    @Test func reusingExtentsStillHonoursCancellationAndLimits() throws {
        let bytes = ProgressiveTests.progressiveJPEG
        let envelope = try JPEGEnvelope.validate(bytes, limits: .init())
        #expect(throws: CodecError.self) {
            try NativeOperation.$current.withValue(.init(seconds: Double.leastNonzeroMagnitude)) {
                var parser = MarkerReader(validated: envelope)
                return try parser.parse()
            }
        }
        #expect(throws: CodecError.self) {
            try JPEGEnvelope.validate(bytes, limits: .init(maximumDimension: 1))
        }
    }
}
