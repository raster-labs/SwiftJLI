// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite("Qualified synchronous JPEG caller storage")
struct QualifiedJPEGTests {
    private func storage<R>(_ count: Int, _ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        defer { pointer.deallocate() }
        pointer.initializeMemory(as: UInt8.self, repeating: 0xA7, count: count)
        return try body(.init(start: pointer, count: count))
    }

    @Test("Independent 12-bit restart samples use exact caller little-endian storage")
    func losslessOracle() {
        let expected = LosslessRestartTests.expected12.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
        storage(QualifiedJPEGDecoder.losslessMonochromeWorkspaceByteCount) { workspace in
            storage(expected.count + 32) { guarded in
                LosslessRestartTests.cjpegRestart12.withUnsafeBytes { input in
                    let output = UnsafeMutableRawBufferPointer(rebasing: guarded[16..<(16 + expected.count)])
                    guard case .success(let plan) = decoder.inspectLosslessMonochrome(input, workspace: workspace),
                          case .success(let result) = decoder.decodeLosslessMonochrome(input, into: output, workspace: workspace) else {
                        Issue.record("Independent lossless decode failed"); return
                    }
                    #expect(plan == result && result.precision == 12)
                    #expect(Array(output) == expected)
                    #expect(guarded.prefix(16).allSatisfy { $0 == 0xA7 })
                    #expect(guarded.suffix(16).allSatisfy { $0 == 0xA7 })
                    if case .success = decoder.decodeLosslessMonochrome(input, into: .init(rebasing: output.dropLast()), workspace: workspace) {
                        Issue.record("Undersized output accepted")
                    }
                }
            }
        }
    }

    @Test("Cancellation and malformed input return scalar failures and permit reuse")
    func cancellationAndReuse() {
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
        storage(QualifiedJPEGDecoder.losslessMonochromeWorkspaceByteCount) { workspace in
            LosslessRestartTests.cjpegRestart12.withUnsafeBytes { input in
                let cancel = QualifiedCancellation(isCancelled: { _ in true })
                guard case .failure(let failure) = decoder.inspectLosslessMonochrome(input, workspace: workspace, cancellation: cancel) else {
                    Issue.record("Cancelled operation succeeded"); return
                }
                #expect(failure.kind == .cancelled)
                guard case .success = decoder.inspectLosslessMonochrome(input, workspace: workspace) else {
                    Issue.record("Cancelled workspace cannot be reused"); return
                }
                if case .success = decoder.inspectLosslessMonochrome(input, workspace: .init(rebasing: workspace.dropLast())) {
                    Issue.record("Undersized workspace accepted")
                }
                [UInt8(0), 1, 2].withUnsafeBytes { malformed in
                    if case .success = decoder.inspectLosslessMonochrome(malformed, workspace: workspace) {
                        Issue.record("Malformed SOI accepted")
                    }
                }
            }
        }
    }

    @Test("Independent baseline chroma fixtures preserve 12N arena and oracle bound 3",
          arguments: ChromaReferenceFixtures.all.filter { $0.name.hasPrefix("baseline_") })
    func baselineOracle(_ fixture: ChromaReferenceFixtures.Fixture) throws {
        let encoded = try #require(Data(base64Encoded: fixture.jpeg))
        let oracle = try #require(Data(base64Encoded: fixture.rgb))
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
        storage(QualifiedJPEGDecoder.baselineHeaderWorkspaceByteCount) { header in
            encoded.withUnsafeBytes { input in
                guard case .success(let info) = decoder.inspectBaselineRGB(input, headerWorkspace: header) else {
                    Issue.record("Baseline inspection failed"); return
                }
                #expect(info.outputByteCount == fixture.width * fixture.height * 3)
                #expect(info.arenaByteCount == fixture.width * fixture.height * 12)
                storage(info.workspaceByteCount) { workspace in
                    storage(info.arenaByteCount + 32) { guarded in
                        let arena = UnsafeMutableRawBufferPointer(rebasing: guarded[16..<(16 + info.arenaByteCount)])
                        guard case .success(let result) = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace) else {
                            Issue.record("Baseline decode failed"); return
                        }
                        #expect(result == info)
                        let actual = Array(arena.prefix(info.outputByteCount))
                        #expect(zip(actual, oracle).allSatisfy { abs(Int($0) - Int($1)) <= 3 })
                        #expect(guarded.prefix(16).allSatisfy { $0 == 0xA7 })
                        #expect(guarded.suffix(16).allSatisfy { $0 == 0xA7 })
                        if case .success = decoder.decodeBaselineRGB(input, arena: .init(rebasing: arena.dropLast()), workspace: workspace) {
                            Issue.record("Undersized full arena accepted")
                        }
                    }
                }
            }
        }
    }

    private func decodedLossless(_ bytes: [UInt8], decoder: QualifiedJPEGDecoder = .init(profile: .jliswift060)) -> [UInt8]? {
        storage(QualifiedJPEGDecoder.losslessMonochromeWorkspaceByteCount) { work in
            bytes.withUnsafeBytes { input in
                guard case .success(let info) = decoder.inspectLosslessMonochrome(input, workspace: work) else { return nil }
                return storage(info.outputByteCount) { output in
                    guard case .success = decoder.decodeLosslessMonochrome(input, into: output, workspace: work) else { return nil }
                    return Array(output)
                }
            }
        }
    }
    @Test("All predictors, point transforms and restart regions retain exact samples", arguments: 1...7)
    func prediction(_ predictor: Int) throws {
        let width = 17, height = 21
        let words = (0..<(width * height)).map { UInt16(($0 * 89) & 4095) }
        let bytes = words.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
        for rows in [0, 1, 4, 25] { for pt in [0, 2] {
            var config = JLIEncoderConfiguration(lossless: true, losslessPredictor: predictor)
            config.losslessPrecision = 12; config.losslessPointTransform = pt; config.restartInterval = width * rows
            let encoded = try JLIEncoder().encode(image, configuration: config)
            let expected = words.map { ($0 >> pt) << pt }.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
            #expect(decodedLossless(encoded) == expected)
        } }
    }

    @Test("Checked limits, disjointness and alignment reject before publication")
    func admissionFailures() {
        let bytes = LosslessRestartTests.cjpegRestart12
        let count = QualifiedJPEGDecoder.losslessMonochromeWorkspaceByteCount
        storage(count + 16) { backing in
            bytes.withUnsafeBytes { input in
                let aligned = UnsafeMutableRawBufferPointer(rebasing: backing[..<count])
                let misaligned = UnsafeMutableRawBufferPointer(rebasing: backing[1..<(count + 1)])
                let ordinary = QualifiedJPEGDecoder(profile: .jliswift060)
                if case .success = ordinary.inspectLosslessMonochrome(input, workspace: misaligned) { Issue.record("Misalignment accepted") }
                for limits in [QualifiedJPEGDecoder.Limits(maximumEncodedBytes: input.count - 1),
                    .init(maximumPixels: 1), .init(maximumDecodedBytes: 1), .init(maximumDimension: 1),
                    .init(maximumWorkspaceBytes: count - 1), .init(maximumMemoryBytes: input.count + count - 1),
                    .init(deadlineSeconds: 0), .init(deadlineSeconds: .nan)] {
                    if case .success = QualifiedJPEGDecoder(profile: .jliswift060, limits: limits).inspectLosslessMonochrome(input, workspace: aligned) {
                        Issue.record("Limit refused to refuse")
                    }
                }
                if case .success = ordinary.decodeLosslessMonochrome(input, into: aligned, workspace: aligned) {
                    Issue.record("Overlapping output/workspace accepted")
                }
                if case .success = ordinary.inspectLosslessMonochrome(UnsafeRawBufferPointer(aligned), workspace: aligned) {
                    Issue.record("Overlapping input/workspace accepted")
                }
            }
        }
    }

    @Test("Every truncated stream is refused and every single byte mutation is bounded")
    func parserMutations() {
        let bytes = LosslessRestartTests.cjpegRestart12
        for end in 0..<(bytes.count - 2) { #expect(decodedLossless(Array(bytes.prefix(end))) == nil) }
        for offset in bytes.indices {
            var mutation = bytes; mutation[offset] ^= 0xff
            // Either a fully bounded decode or a scalar refusal is permitted.
            _ = decodedLossless(mutation, decoder: .init(profile: .jliswift060,
                limits: .init(maximumPixels: 4096, maximumDecodedBytes: 8192, deadlineSeconds: 1)))
        }
    }

    private struct CancelState { var calls = 0; var stop = Int.max }
    private static let cancellationCheck: QualifiedCancellation.Check = { raw in
        guard let raw else { return false }
        let state = UnsafeMutableRawPointer(mutating: raw).assumingMemoryBound(to: CancelState.self)
        state.pointee.calls += 1
        return state.pointee.calls >= state.pointee.stop
    }
    @Test("In-flight cancellation at early middle and final checkpoints leaves reusable storage")
    func cancellationCheckpoints() throws {
        let fixture = try #require(ChromaReferenceFixtures.all.first { $0.name == "baseline_422_64x18" })
        let jpeg = try #require(Data(base64Encoded: fixture.jpeg))
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
        storage(1 << 20) { workspace in
            storage(fixture.width * fixture.height * 12) { arena in
                jpeg.withUnsafeBytes { input in
                    var state = CancelState()
                    withUnsafeMutablePointer(to: &state) { pointer in
                        let token = QualifiedCancellation(context: pointer, isCancelled: Self.cancellationCheck)
                        guard case .success = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace, cancellation: token) else {
                            Issue.record("Initial baseline decode failed"); return
                        }
                        let checkpoints = pointer.pointee.calls
                        #expect(checkpoints > 10)
                        for stop in [1, checkpoints / 2, checkpoints] {
                            pointer.pointee = .init(calls: 0, stop: stop)
                            guard case .failure(let failure) = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace, cancellation: token) else {
                                Issue.record("In-flight cancellation was ignored"); return
                            }
                            #expect(failure.kind == .cancelled)
                            // The public final publication guard may check an already cancelled callback once more.
                            #expect(pointer.pointee.calls >= stop && pointer.pointee.calls <= stop + 1)
                            guard case .success = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace) else {
                                Issue.record("Storage reuse failed after in-flight cancellation"); return
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Tiny deadline fails and huge finite deadline remains representable")
    func deadlines() {
        let bytes = LosslessRestartTests.cjpegRestart12
        #expect(decodedLossless(bytes, decoder: .init(profile: .jliswift060, limits: .init(deadlineSeconds: 1e-9))) == nil)
        #expect(decodedLossless(bytes, decoder: .init(profile: .jliswift060, limits: .init(deadlineSeconds: Double.greatestFiniteMagnitude))) != nil)
    }

    private func oneSample(precision: UInt8 = 12, tableID: Int = 0, category16: Bool = false) -> [UInt8] {
        var bytes: [UInt8] = [0xff, 0xd8, 0xff, 0xc3, 0, 11, precision, 0, 1, 0, 1, 1, 1, 0x11, 0]
        if category16 {
            bytes += [0xff, 0xc4, 0, 20, UInt8(tableID), 1] + Array(repeating: 0, count: 15) + [16]
        }
        bytes += [0xff, 0xda, 0, 8, 1, 1, UInt8(tableID << 4), 1, 0, 0, 0, 0xff, 0xd9]
        return bytes
    }
    @Test("Precision extremes, sparse tables and category16 retain predecessor samples")
    func tableAndPrecision() {
        for bits: UInt8 in [2, 8, 12, 16] {
            let value = UInt16(1) << (bits - 1)
            #expect(decodedLossless(oneSample(precision: bits)) == [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)])
        }
        for id in [0, 1, 7, 15] {
            #expect(decodedLossless(oneSample(tableID: id)) == [0, 8])
            #expect(decodedLossless(oneSample(tableID: id, category16: true)) == [0, 136])
        }
        var unknown = oneSample(); unknown[20] = 2
        #expect(decodedLossless(unknown) == nil)
        var badParameters = oneSample(); badParameters[23] = 63
        #expect(decodedLossless(badParameters) == nil)
        var padded = oneSample()
        // A single zero pad is legal only when it makes an odd stream even.
        if padded.count.isMultiple(of: 2) { padded.insert(contentsOf: [0xff, 0xfe, 0, 3, 1], at: 2) }
        #expect(decodedLossless(padded + [0]) == [0, 8])
        #expect(decodedLossless(padded + [0, 0]) == nil)
    }

    private func decodedRGB(_ bytes: [UInt8], source: QualifiedJPEGDecoder.SourceColourModel? = nil) -> [UInt8]? {
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060, sourceColourModel: source)
        return storage(QualifiedJPEGDecoder.baselineHeaderWorkspaceByteCount) { header in
            bytes.withUnsafeBytes { input in
                guard case .success(let info) = decoder.inspectBaselineRGB(input, headerWorkspace: header) else { return nil }
                return storage(info.workspaceByteCount) { work in
                    storage(info.arenaByteCount) { arena in
                        guard case .success = decoder.decodeBaselineRGB(input, arena: arena, workspace: work) else { return nil }
                        return Array(arena.prefix(info.outputByteCount))
                    }
                }
            }
        }
    }
    // Generator adapted from JLISwift b6df774 BaselineCallerStorageTests.swift.
    private func sequential(scans: [[Int]], intervals: [Int], redefineQuantization: Bool) -> [UInt8] {
        let width = 17, height = 19, columns = 3, rows = 3
        var data: [UInt8] = [0xff, 0xd8, 0xff, 0xc0, 0, 17, 8, 0, UInt8(height), 0, UInt8(width), 3,
                            1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0]
        for (index, components) in scans.enumerated() {
            let q = UInt8(redefineQuantization ? index + 1 : 1)
            data += [0xff, 0xdb, 0, 67, 0] + Array(repeating: q, count: 64)
            let interval = intervals[index]
            data += [0xff, 0xdd, 0, 4, UInt8(interval >> 8), UInt8(interval & 255)]
            data += [0xff, 0xda, 0, UInt8(6 + 2 * components.count), UInt8(components.count)]
            for component in components { data += [UInt8(component + 1), 0] }
            data += [0, 63, 0]
            var writer = BitWriter(), previous = [Int32](repeating: 0, count: 3), restart = 0
            for mcu in 0..<(columns * rows) {
                if interval > 0, mcu > 0, mcu % interval == 0 {
                    writer.emitRestartMarker(restart); restart += 1
                    previous = [0, 0, 0]
                }
                for component in components {
                    HuffmanEncoder.encodeDC(8 - previous[component], table: StandardHuffmanTables.dcLuminance, writer: &writer)
                    previous[component] = 8
                    HuffmanEncoder.encodeAC(Array(repeating: 0, count: 64), table: StandardHuffmanTables.acLuminance, writer: &writer)
                }
            }
            writer.flush(); data += writer.data
        }
        // Final post-scan changes must not retroactively alter any scan.
        data += [0xff, 0xdd, 0, 4, 0, 7]
        data += [0xff, 0xdb, 0, 67, 0] + Array(repeating: 31, count: 64)
        return data + [0xff, 0xd9]
    }


    @Test("Per-scan DQT and DRI snapshots preserve mixed and separate component output")
    func scanSnapshots() {
        let separate = sequential(scans: [[0], [1], [2]], intervals: [1, 2, 0], redefineQuantization: true)
        #expect(decodedRGB(separate, source: .rgb) == Array(repeating: [UInt8(129), 130, 131], count: 17 * 19).flatMap { $0 })
        let mixed = sequential(scans: [[2, 0], [1]], intervals: [2, 1], redefineQuantization: false)
        #expect(decodedRGB(mixed, source: .rgb) == Array(repeating: 129, count: 17 * 19 * 3))
        #expect(decodedRGB(sequential(scans: [[0, 1], [1, 2]], intervals: [0, 0], redefineQuantization: false)) == nil)
        #expect(decodedRGB(sequential(scans: [[0, 1]], intervals: [0], redefineQuantization: false)) == nil)
    }

    @Test("Wide reconstruction crosses bounded IDCT tiles without changing samples")
    func wideTiles() throws {
        let width = 1025, height = 3
        let bytes = (0..<(width * height * 3)).map { UInt8(($0 * 39 + $0 / 7) & 255) }
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint8, colorModel: .rgb, data: bytes)
        var config = JLIEncoderConfiguration.default; config.chromaSubsampling = .yuv444; config.adaptiveQuantization = false
        let jpeg = try JLIEncoder().encode(image, configuration: config)
        let output = try #require(decodedRGB(jpeg))
        let ordinary = try JLIDecoder().decode(from: jpeg).data
        #expect(output.count == ordinary.count)
        // Current owning Apple DSP may round differently from the pinned pure Swift profile.
        #expect(zip(output, ordinary).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
        config.colorSpace = .xyb
        let xyb = try JLIEncoder().encode(image, configuration: config)
        let xybOutput = try #require(decodedRGB(xyb))
        let xybOrdinary = try JLIDecoder().decode(from: xyb).data
        #expect(zip(xybOutput, xybOrdinary).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    }

    @Test("Concurrent readers use independent synchronous scratch and exact immutable input")
    func concurrentBorrowers() async {
        let bytes = LosslessRestartTests.cjpegRestart12
        let expected = LosslessRestartTests.expected12.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask { Self().decodedLossless(bytes) == expected }
            }
            for await matches in group { #expect(matches) }
        }
    }

    @Test("Missing referenced DQT is refused before output writes and normal decode recovers")
    func missingQuantization() throws {
        let fixture = try #require(ChromaReferenceFixtures.all.first { $0.name == "baseline_422_64x18" })
        let valid = Array(try #require(Data(base64Encoded: fixture.jpeg)))
        var missing = Array(valid.prefix(2)), offset = 2
        while offset + 4 < valid.count && valid[offset + 1] != 0xda {
            let end = offset + 2 + Int(valid[offset + 2]) * 256 + Int(valid[offset + 3])
            if valid[offset + 1] != 0xdb { missing += valid[offset..<end] }
            offset = end
        }
        missing += valid[offset...]
        #expect(missing.count < valid.count)
        let decoder = QualifiedJPEGDecoder(profile: .jliswift060)
        storage(1 << 20) { workspace in
            storage(fixture.width * fixture.height * 12) { arena in
                missing.withUnsafeBytes { input in
                    guard case .failure(let failure) = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace) else {
                        Issue.record("Missing DQT produced successful pixels"); return
                    }
                    #expect(failure.code == 178 && failure.kind == .decoding)
                    #expect(arena.allSatisfy { $0 == 0xA7 })
                }
                valid.withUnsafeBytes { input in
                    guard case .success = decoder.decodeBaselineRGB(input, arena: arena, workspace: workspace) else {
                        Issue.record("Workspace cannot recover after missing DQT"); return
                    }
                }
            }
        }
    }
}
