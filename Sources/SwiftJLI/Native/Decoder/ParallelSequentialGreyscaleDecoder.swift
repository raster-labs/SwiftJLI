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
        let bytes = UnsafeMutableRawBufferPointer(start: base,
            count: try checkedMultiply(pixels.count, MemoryLayout<Float>.stride))
        let maximum = Float((1 << precision) - 1)
        for index in 0..<pixels.count {
            if index & 4095 == 0 { try NativeOperation.check() }
            let sample = pixels[index]
            guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
            if floatOutput {
                // All supported hosts are little-endian; retain the portable
                // byte order if this internal helper is exercised elsewhere.
                if UInt32(littleEndian: 1) != 1 {
                    let bits = sample.bitPattern
                    for byte in 0..<4 { bytes[index * 4 + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
                }
            } else {
                let value = UInt16(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                bytes[index * bytesPerSample] = UInt8(truncatingIfNeeded: value)
                if bytesPerSample == 2 { bytes[index * 2 + 1] = UInt8(value >> 8) }
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
        let output = destination.bytes.baseAddress!
        for index in 0..<(coefficients.count / 64) {
            if index & 63 == 0 { try NativeOperation.check() }
            let block = firstBlock + index, x = block % blocksPerRow * 8, y = block / blocksPerRow * 8
            guard x < width, y < height else { continue }
            let group = index / 1024, localBlock = index % 1024
            let tile = source + group * 1024 * 64 * MemoryLayout<Int32>.stride + localBlock * 64 * bps
            let bytes = min(8, width - x) * bps
            for row in 0..<min(8, height - y) {
                memcpy(output + (y + row) * destination.rowBytes + x * bps, tile + row * 8 * bps, bytes)
            }
        }
    }
}
