// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Bounded joined reconstruction owns only internal coefficient/output and
/// Float scratch windows. Provider memory stays on the calling thread: workers
/// compact samples into their consumed internal slots, join, then the caller
/// copies complete byte tiles into the validated destination.
enum ParallelSequentialGreyscaleDecoder {
    static func decode(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable, lookup: ACLookahead?,
        quantTable: [Float], plan: SequentialGreyscalePlan,
        width: Int, height: Int, precision: Int, restartInterval: Int,
        floatOutput: Bool, destination: BorrowedSampleDestination
    ) throws {
        let capacity = try checkedMultiply(plan.batchBlocks, 64)
        let scratchCount = plan.blockLocalIDCT ? 0 : capacity
        // A zero-capacity uninitialised constructor writes the shared empty
        // Array storage on this toolchain. FMA needs no scratch or such write.
        var scratch: [Float] = scratchCount == 0 ? [] :
            [Float](unsafeUninitializedCapacity: scratchCount) { _, count in count = scratchCount }
        try quantTable.withUnsafeBufferPointer { qt in
            try scratch.withUnsafeMutableBufferPointer { workspace in
                try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                    dcTable: dcTable, acTable: acTable, lookup: lookup,
                    blocksPerRow: plan.blocksPerRow, blockRows: plan.blockRows,
                    precision: precision, restartInterval: restartInterval,
                    windowBlocks: plan.batchBlocks, transformGroupBlocks: plan.transformGroupBlocks) { coefficients, first in
                    try reconstructWindow(coefficients, quantTable: qt, scratch: workspace,
                        precision: precision,
                        bytesPerSample: destination.bytesPerSample, floatOutput: floatOutput)
                    // No provider pointer enters reconstructWindow or its carrier.
                    // Every worker has joined before this caller-thread scatter.
                    try scatterWindow(coefficients, firstBlock: first, blocksPerRow: plan.blocksPerRow,
                        width: width, height: height, destination: destination)
                }
            }
        }
    }

    /// All three owners remain in enclosing synchronous borrows. Each logical
    /// group exclusively owns one disjoint 1024-block coefficient/output region
    /// and its corresponding scratch region; the quantisation table is read-only.
    /// No parent access occurs during perform, which joins on success and error.
    /// Each worker restores any temporary Float binding before it returns. The
    /// caller subsequently reads only raw bytes, then entropy fully resets every
    /// Int32 block before reuse. No provider pointer or asynchronous owner is held.
    private struct WindowBuffers: @unchecked Sendable {
        let coefficients: UnsafeMutablePointer<Int32>
        let quantTable: UnsafePointer<Float>
        let scratch: UnsafeMutablePointer<Float>
    }

    static func reconstructWindow(
        _ coefficients: UnsafeMutableBufferPointer<Int32>, quantTable: UnsafeBufferPointer<Float>,
        scratch: UnsafeMutableBufferPointer<Float>, zeroACGroups: UInt8? = nil,
        precision: Int, bytesPerSample: Int, floatOutput: Bool
    ) throws {
        let blockLocal = BlockLocalIDCT.available && NativeDSP.usesAccelerate
        guard !coefficients.isEmpty, coefficients.count % 64 == 0,
              coefficients.count <= SequentialGreyscalePlan.maximumWindowBlocks * 64,
              (blockLocal || scratch.count >= coefficients.count), quantTable.count >= 64,
              precision == 8 || precision == 12,
              floatOutput ? bytesPerSample == 4 : (bytesPerSample == 1 && precision <= 8) || bytesPerSample == 2,
              let base = coefficients.baseAddress, let qt = quantTable.baseAddress else {
            throw JLIError.decodingFailed("Invalid bounded reconstruction window")
        }
        let blocks = coefficients.count / 64, groups = (blocks - 1) / 1024 + 1
        let activeMask: UInt8 = groups == 8 ? .max : (UInt8(1) << groups) - 1
        if let zeroACGroups, zeroACGroups & ~activeMask != 0 {
            throw JLIError.decodingFailed("Invalid bounded reconstruction proof")
        }
        if blockLocal {
            // Each canonical slot retains its original byte layout for scatter.
            // The transform consumes all Int32 values before Float compaction.
            // Neither phase accesses caller-owned destination storage.
            for group in 0..<groups {
                let first = group * 1024, count = min(1024, blocks - first) * 64
                let slot = base + first * 64
                if try BlockLocalIDCT.reconstructAndCompact(
                    .init(start: slot, count: count),
                    quantiser: quantTable, precision: precision,
                    bytesPerSample: bytesPerSample, floatOutput: floatOutput) {
                    continue
                }
                try BlockLocalIDCT.reconstruct(.init(start: slot, count: count),
                    quantiser: quantTable, precision: precision)
                try slot.withMemoryRebound(to: Float.self, capacity: count) { pixels in
                    try compactPixelsInPlace(.init(start: pixels, count: count), precision: precision,
                        bytesPerSample: bytesPerSample, floatOutput: floatOutput)
                }
            }
            return
        }
        guard let workspace = scratch.baseAddress else {
            throw JLIError.decodingFailed("Missing bounded reconstruction scratch")
        }
        let buffers = WindowBuffers(coefficients: base, quantTable: qt, scratch: workspace)
        try NativeOperation.perform(iterations: groups) { group in
            let first = group * 1024, count = min(1024, blocks - first), samples = count * 64
            let coefficients = buffers.coefficients + first * 64
            let scratch = buffers.scratch + first * 64
            var centre = Float(1 << (precision - 1))
            var low: Float = 0, high = Float((1 << precision) - 1)
            let knownZeroAC = zeroACGroups.map { $0 & (UInt8(1) << group) != 0 }
            let dcOnly = knownZeroAC != false && AccelerateDSP.prepareDCOnlyDCTBatch(
                zigzag: UnsafePointer(coefficients), quantTable: buffers.quantTable,
                scratch: scratch, blockCount: count)
            if dcOnly {
                jliDSP_vsadd(scratch, 1, &centre, scratch, 1, count)
                jliDSP_vclip(scratch, 1, &low, &high, scratch, 1, count)
                // All coefficient reads have completed. Raw-byte writes preserve
                // the Int32 binding; no coefficient value is read again.
                try encodeConstantTiles(UnsafeBufferPointer(start: scratch, count: count),
                    into: .init(start: coefficients, count: samples * MemoryLayout<Int32>.stride),
                    precision: precision, bytesPerSample: bytesPerSample, floatOutput: floatOutput)
            } else {
                AccelerateDSP.packDequantizedDCTBatch(zigzag: UnsafePointer(coefficients),
                    quantTable: buffers.quantTable, scratch: scratch, blockCount: count)
                try coefficients.withMemoryRebound(to: Float.self, capacity: samples) { pixels in
                    AccelerateDSP.inverseDCTBatchPacked(output: pixels, scratch: scratch, blockCount: count)
                    jliDSP_vsadd(pixels, 1, &centre, pixels, 1, samples)
                    jliDSP_vclip(pixels, 1, &low, &high, pixels, 1, samples)
                    try compactPixelsInPlace(.init(start: pixels, count: samples), precision: precision,
                        bytesPerSample: bytesPerSample, floatOutput: floatOutput)
                }
            }
        }
    }

    /// Raw-buffer byte access is untyped and does not change memory binding.
    /// Float is trivial. Sample i is read before its packed bytes are written;
    /// with 1/2 output bytes versus 4 source bytes, the written prefix cannot
    /// reach any later Float. Consumed Float values are never read again. The
    /// surrounding withMemoryRebound restores Int32 on normal/throwing returns.
    /// See Swift stdlib UnsafeRawBufferPointer documentation (untyped byte view).
    static func compactPixelsInPlace(_ pixels: UnsafeMutableBufferPointer<Float>, precision: Int,
                                     bytesPerSample: Int, floatOutput: Bool) throws {
        guard precision == 8 || precision == 12,
              floatOutput ? bytesPerSample == 4 : (bytesPerSample == 1 && precision <= 8) || bytesPerSample == 2,
              let base = pixels.baseAddress else {
            throw JLIError.decodingFailed("Invalid compacted sample layout")
        }
        _ = try checkedMultiply(pixels.count, MemoryLayout<Float>.stride)
        let rawBase = UnsafeMutableRawPointer(base)
        let maximum = Float((1 << precision) - 1)
        let zero = SIMD8<Float>(repeating: 0)
        let maxVec = SIMD8<Float>(repeating: maximum)
        let magicBias = SIMD8<Float>(repeating: 8_388_608.0)
        let absMask = SIMD8<UInt32>(repeating: 0x7FFF_FFFF)
        let total = pixels.count

        for chunkStart in stride(from: 0, to: total, by: 4096) {
            try NativeOperation.check()
            let chunkEnd = min(total, chunkStart + 4096)
            var index = chunkStart
            if floatOutput {
                while index + 8 <= chunkEnd {
                    let vec = UnsafeRawPointer(base + index).loadUnaligned(as: SIMD8<Float>.self)
                    let rawBits = unsafeBitCast(vec, to: SIMD8<UInt32>.self)
                    if (rawBits & absMask).max() <= 0x7F7F_FFFF {
                        if UInt32(littleEndian: 1) != 1 {
                            for lane in 0..<8 {
                                let bits = rawBits[lane]
                                for byte in 0..<4 {
                                    rawBase.storeBytes(of: UInt8(truncatingIfNeeded: bits >> (byte * 8)),
                                                       toByteOffset: (index + lane) * 4 + byte, as: UInt8.self)
                                }
                            }
                        }
                        index += 8
                    } else {
                        break
                    }
                }
                while index < chunkEnd {
                    let sample = base[index]
                    guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                    if UInt32(littleEndian: 1) != 1 {
                        let bits = sample.bitPattern
                        for byte in 0..<4 {
                            rawBase.storeBytes(of: UInt8(truncatingIfNeeded: bits >> (byte * 8)),
                                               toByteOffset: index * 4 + byte, as: UInt8.self)
                        }
                    }
                    index += 1
                }
            } else if bytesPerSample == 2 {
                while index + 8 <= chunkEnd {
                    let vec = UnsafeRawPointer(base + index).loadUnaligned(as: SIMD8<Float>.self)
                    let rawBits = unsafeBitCast(vec, to: SIMD8<UInt32>.self)
                    if (rawBits & absMask).max() <= 0x7F7F_FFFF {
                        var clamped = vec.replacing(with: zero, where: vec .< zero)
                        clamped = clamped.replacing(with: maxVec, where: clamped .> maxVec)
                        let rounded = clamped.rounded(.toNearestOrAwayFromZero)
                        let biasedBits = unsafeBitCast(rounded + magicBias, to: SIMD8<UInt32>.self)
                        let words = SIMD8<UInt16>(truncatingIfNeeded: biasedBits)
                        if UInt16(littleEndian: 1) == 1 {
                            rawBase.storeBytes(of: words, toByteOffset: index * 2, as: SIMD8<UInt16>.self)
                        } else {
                            for lane in 0..<8 {
                                let value = words[lane]
                                rawBase.storeBytes(of: UInt8(truncatingIfNeeded: value), toByteOffset: (index + lane) * 2, as: UInt8.self)
                                rawBase.storeBytes(of: UInt8(value >> 8), toByteOffset: (index + lane) * 2 + 1, as: UInt8.self)
                            }
                        }
                        index += 8
                    } else {
                        break
                    }
                }
                while index < chunkEnd {
                    let sample = base[index]
                    guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                    let value = UInt16(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                    rawBase.storeBytes(of: UInt8(truncatingIfNeeded: value), toByteOffset: index * 2, as: UInt8.self)
                    rawBase.storeBytes(of: UInt8(value >> 8), toByteOffset: index * 2 + 1, as: UInt8.self)
                    index += 1
                }
            } else {
                while index + 8 <= chunkEnd {
                    let vec = UnsafeRawPointer(base + index).loadUnaligned(as: SIMD8<Float>.self)
                    let rawBits = unsafeBitCast(vec, to: SIMD8<UInt32>.self)
                    if (rawBits & absMask).max() <= 0x7F7F_FFFF {
                        var clamped = vec.replacing(with: zero, where: vec .< zero)
                        clamped = clamped.replacing(with: maxVec, where: clamped .> maxVec)
                        let rounded = clamped.rounded(.toNearestOrAwayFromZero)
                        let biasedBits = unsafeBitCast(rounded + magicBias, to: SIMD8<UInt32>.self)
                        let outBytes = SIMD8<UInt8>(truncatingIfNeeded: biasedBits)
                        rawBase.storeBytes(of: outBytes, toByteOffset: index, as: SIMD8<UInt8>.self)
                        index += 8
                    } else {
                        break
                    }
                }
                while index < chunkEnd {
                    let sample = base[index]
                    guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                    let value = UInt8(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                    rawBase.storeBytes(of: value, toByteOffset: index, as: UInt8.self)
                    index += 1
                }
            }
        }
    }

    private static func encodeConstantTiles(_ values: UnsafeBufferPointer<Float>,
                                            into bytes: UnsafeMutableRawBufferPointer,
                                            precision: Int, bytesPerSample: Int, floatOutput: Bool) throws {
        let maximum = Float((1 << precision) - 1)
        for block in 0..<values.count {
            if block & 63 == 0 { try NativeOperation.check() }
            let sample = values[block]
            guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
            if floatOutput {
                let bits = sample.bitPattern
                for pixel in 0..<64 { for byte in 0..<4 {
                    bytes[(block * 64 + pixel) * 4 + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8))
                } }
            } else {
                let value = UInt16(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                for pixel in 0..<64 {
                    bytes[(block * 64 + pixel) * bytesPerSample] = UInt8(truncatingIfNeeded: value)
                    if bytesPerSample == 2 { bytes[(block * 64 + pixel) * 2 + 1] = UInt8(value >> 8) }
                }
            }
        }
    }

    /// The destination layout was checked before entering the decoder. Each
    /// group retains its original 4-byte coefficient slot; compacted byte tiles
    /// occupy its prefix. Copy only active rows/columns, preserving all padding.
    static func scatterWindow(_ coefficients: UnsafeMutableBufferPointer<Int32>,
                                      firstBlock: Int, blocksPerRow: Int, width: Int, height: Int,
                                      destination: BorrowedSampleDestination) throws {
        let source = UnsafeRawPointer(coefficients.baseAddress!), bps = destination.bytesPerSample
        let output = destination.bytes.baseAddress!, rowStride = destination.rowBytes
        let blockCount = coefficients.count / 64
        var col = firstBlock % blocksPerRow
        var rowBlock = firstBlock / blocksPerRow
        for index in 0..<blockCount {
            if index & 63 == 0 { try NativeOperation.check() }
            let x = col * 8, y = rowBlock * 8
            col += 1
            if col == blocksPerRow {
                col = 0
                rowBlock += 1
            }
            guard x < width, y < height else { continue }
            let group = index >> 10, localBlock = index & 1023
            let tile = source + group * (1024 * 64 * MemoryLayout<Int32>.stride) + localBlock * 64 * bps
            let dstBase = output + y * rowStride + x * bps
            if x + 8 <= width && y + 8 <= height {
                switch bps {
                case 2:
                    for row in 0..<8 {
                        memcpy(dstBase + row * rowStride, tile + row * 16, 16)
                    }
                case 1:
                    for row in 0..<8 {
                        memcpy(dstBase + row * rowStride, tile + row * 8, 8)
                    }
                case 4:
                    for row in 0..<8 {
                        memcpy(dstBase + row * rowStride, tile + row * 32, 32)
                    }
                default:
                    let bytes = 8 * bps
                    for row in 0..<8 {
                        memcpy(dstBase + row * rowStride, tile + row * bytes, bytes)
                    }
                }
            } else {
                let bytes = min(8, width - x) * bps
                for row in 0..<min(8, height - y) {
                    memcpy(dstBase + row * rowStride, tile + row * 8 * bps, bytes)
                }
            }
        }
    }
}
