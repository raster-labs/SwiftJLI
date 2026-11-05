// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class WindowCancellationState: Sendable {
    let polls = Mutex(0)
    let releases = Mutex(0)
}

private final class WindowCancellationOwner: Sendable {
    let state: WindowCancellationState
    init(_ state: WindowCancellationState) { self.state = state }
    func poll() throws {
        let calls = state.polls.withLock { $0 += 1; return $0 }
        if calls >= 12 { throw CancellationError() }
    }
    deinit { state.releases.withLock { $0 += 1 } }
}

@Suite struct ParallelGreyscaleWindowTests {
    private static func bytes(_ samples: [Float], precision: Int, floating: Bool) -> [UInt8] {
        let maximum = Float((1 << precision) - 1), bps = floating ? 4 : precision == 8 ? 1 : 2
        var result: [UInt8] = []
        result.reserveCapacity(samples.count * bps)
        for sample in samples {
            let bits = floating ? sample.bitPattern
                : UInt32(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
            for byte in 0..<bps { result.append(UInt8(truncatingIfNeeded: bits >> (byte * 8))) }
        }
        return result
    }

    @Test(arguments: [8, 12], [false, true])
    func byteCompactionPreservesUnconsumedSamplesAndGuards(precision: Int, floating: Bool) throws {
        let values: [Float] = [-1, 0, 0.49, 0.5, 1.5, 127.5, 255.5, 2048.5, 4094.5, 4095, 4096]
        let samples = (0..<8195).map { values[$0 % values.count] }
        let expected = Self.bytes(samples, precision: precision, floating: floating)
        let sentinel: Float = 987654
        var buffer = [Float](repeating: sentinel, count: 3) + samples + [Float](repeating: sentinel, count: 5)
        try buffer.withUnsafeMutableBufferPointer {
            try ParallelSequentialGreyscaleDecoder.compactPixelsInPlace(
                .init(rebasing: $0[3..<(3 + samples.count)]), precision: precision,
                bytesPerSample: floating ? 4 : precision == 8 ? 1 : 2, floatOutput: floating)
        }
        buffer.withUnsafeBytes { #expect($0[12..<(12 + expected.count)].elementsEqual(expected)) }
        #expect(buffer.prefix(3).allSatisfy { $0 == sentinel })
        #expect(buffer.suffix(5).allSatisfy { $0 == sentinel })
    }

    @Test func compactionThrowsRestoreBindingAndLeaveUnreadSuffixIntact() throws {
        for cancelled in [false, true] {
            let count = 8192, value = Float(123.5).bitPattern
            var words = [Int32](repeating: Int32(bitPattern: value), count: count)
            if !cancelled { words[4100] = Int32(bitPattern: Float.nan.bitPattern) }
            let polls = Mutex(0)
            let outcome = Result {
                try NativeOperation.withSynchronousCancellation({
                    let calls = polls.withLock { $0 += 1; return $0 }
                    if cancelled && calls >= 3 { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 120)) {
                        try words.withUnsafeMutableBufferPointer { buffer in
                            try buffer.baseAddress!.withMemoryRebound(to: Float.self, capacity: count) {
                                try ParallelSequentialGreyscaleDecoder.compactPixelsInPlace(
                                    .init(start: $0, count: count), precision: 12, bytesPerSample: 2, floatOutput: false)
                            }
                        }
                    }
                }
            }
            switch outcome {
            case .success: Issue.record("Expected compaction to stop")
            case .failure(let error): #expect(cancelled ? error is CancellationError : error is JLIError)
            }
            // Access after the throwing rebind is Int32 again. Packed prefix
            // writes cannot damage any later, unread Float representation.
            #expect(words[0] != Int32(bitPattern: value))
            #expect(words.last == Int32(bitPattern: value))
            words.withUnsafeMutableBufferPointer { $0.baseAddress!.update(repeating: 7, count: count) }
            #expect(words.allSatisfy { $0 == 7 })
        }
    }

    @Test(arguments: [false, true])
    func joinedCanonicalGroupsPreserveBitsProofFallbackAndBounds(floating: Bool) throws {
        for backend in Decoder.capabilities.availableBackends {
            for blocks in [2050, 8192] {
                let samples = blocks * 64, bps = floating ? 4 : 2
                var original = [Int32](repeating: 0, count: samples)
                for block in 0..<blocks {
                    original[block * 64] = Int32(block % 511 - 255)
                    if (block / 1024) % 2 == 1 { original[block * 64 + 63] = Int32(block % 31 + 1) }
                }
                let table = (0..<64).map { Float($0 % 7 + 1) }
                let groups = (blocks - 1) / 1024 + 1
                let proof = (0..<groups).reduce(UInt8(0)) { $1 % 2 == 0 ? $0 | (UInt8(1) << $1) : $0 }
                let expected = NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                    var result: [UInt8] = []
                    for first in stride(from: 0, to: blocks, by: 1024) {
                        let count = min(1024, blocks - first)
                        var pixels = [Float](repeating: 0, count: count * 64), scratch = pixels
                        original.withUnsafeBufferPointer { c in table.withUnsafeBufferPointer { q in
                            pixels.withUnsafeMutableBufferPointer { p in scratch.withUnsafeMutableBufferPointer { s in
                                AccelerateDSP.inverseDCTBatchDequantized(zigzag: c.baseAddress! + first * 64,
                                    quantTable: q.baseAddress!, output: p.baseAddress!, scratch: s.baseAddress!, blockCount: count)
                                var centre: Float = 2048, low: Float = 0, high: Float = 4095
                                jliDSP_vsadd(p.baseAddress!, 1, &centre, p.baseAddress!, 1, p.count)
                                jliDSP_vclip(p.baseAddress!, 1, &low, &high, p.baseAddress!, 1, p.count)
                            } }
                        } }
                        result += Self.bytes(pixels, precision: 12, floating: floating)
                    }
                    return result
                }
                for workers in blocks == 8192 ? [8] : [1, 2, 3] {
                    for known in [false, true] {
                        let sentinel: Int32 = 123456
                        var coefficients = [Int32](repeating: sentinel, count: 3) + original + [Int32](repeating: sentinel, count: 5)
                        var scratch = [Float](repeating: 123456, count: samples + 8)
                        try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: workers)) {
                            try coefficients.withUnsafeMutableBufferPointer { c in
                                try table.withUnsafeBufferPointer { q in try scratch.withUnsafeMutableBufferPointer { s in
                                    try ParallelSequentialGreyscaleDecoder.reconstructWindow(
                                        .init(rebasing: c[3..<(3 + samples)]), quantTable: q,
                                        scratch: .init(rebasing: s[3..<(3 + samples)]),
                                        zeroACGroups: known ? proof : nil, precision: 12,
                                        bytesPerSample: bps, floatOutput: floating)
                                } }
                            }
                        }
                        coefficients.withUnsafeBytes { bytes in
                            for first in stride(from: 0, to: blocks, by: 1024) {
                                let count = min(1024, blocks - first) * 64 * bps
                                let start = 12 + first * 64 * 4, expectedStart = first * 64 * bps
                                #expect(bytes[start..<(start + count)].elementsEqual(expected[expectedStart..<(expectedStart + count)]))
                            }
                        }
                        #expect(coefficients.prefix(3).allSatisfy { $0 == sentinel })
                        #expect(coefficients.suffix(5).allSatisfy { $0 == sentinel })
                        #expect(scratch.prefix(3).allSatisfy { $0 == 123456 })
                        #expect(scratch.suffix(5).allSatisfy { $0 == 123456 })
                    }
                }
            }
        }
    }

    @Test func cancelledJoinedWindowReleasesContextsBeforeBufferReuse() throws {
        let samples = 8192 * 64
        var coefficients = [Int32](repeating: 0, count: samples)
        for block in 0..<8192 { coefficients[block * 64 + 1] = 3 }
        let table = [Float](repeating: 1, count: 64)
        var scratch = [Float](repeating: 0, count: samples)
        let state = WindowCancellationState()
        func reconstruct() throws {
            try coefficients.withUnsafeMutableBufferPointer { c in
                try table.withUnsafeBufferPointer { q in try scratch.withUnsafeMutableBufferPointer { s in
                    try ParallelSequentialGreyscaleDecoder.reconstructWindow(c, quantTable: q, scratch: s,
                        precision: 12, bytesPerSample: 2, floatOutput: false)
                } }
            }
        }
        func cancelledScope() throws {
            let owner = WindowCancellationOwner(state)
            try NativeOperation.withSynchronousCancellation({ try owner.poll() }) {
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                    try reconstruct()
                }
            }
        }
        #expect(throws: CancellationError.self) { try cancelledScope() }
        // Every joined worker retained the operation callback. Its capture must
        // be released before either borrowed buffer can be reused or destroyed.
        #expect(state.releases.withLock { $0 } == 1)
        let completedPolls = state.polls.withLock { $0 }
        coefficients.withUnsafeMutableBufferPointer { $0.baseAddress!.update(repeating: 0, count: samples) }
        try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
            try reconstruct()
        }
        #expect(state.polls.withLock { $0 } == completedPolls)
        coefficients.withUnsafeBytes { bytes in
            for group in 0..<8 {
                let start = group * 1024 * 64 * 4
                #expect((0..<(1024 * 64)).allSatisfy { bytes[start + $0 * 2] == 0 && bytes[start + $0 * 2 + 1] == 8 })
            }
        }
    }

    @Test func concurrentPublicDecodersKeepIndependentGroupedWindows() async throws {
        let width = 513, height = 513
        let image = try JLIImage(width: width, height: height, pixelFormat: .uint8, colorModel: .grayscale,
            data: (0..<(width * height)).map { UInt8(truncatingIfNeeded: $0 * 17 + $0 / width * 31) })
        let data = Data(try JLIEncoder().encode(image))
        let decoder = try Decoder()
        let reference = try await decoder.decode(data, options: .init(resourceLimits: try ResourceLimits(maximumWorkers: 1)))
        let expected = try reference.image.storage.withUnsafeBytes { Array($0) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let decoder = try Decoder()
                    let decoded = try await decoder.decode(data,
                        options: .init(resourceLimits: try ResourceLimits(maximumWorkers: 2)))
                    #expect(try decoded.image.storage.withUnsafeBytes { Array($0) } == expected)
                }
            }
            try await group.waitForAll()
        }
    }
}
