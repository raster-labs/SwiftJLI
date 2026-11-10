// SPDX-License-Identifier: Apache-2.0

/// An outlined C-only entropy route. Declining the route cannot allocate a
/// coefficient slot, consume reader state, or call the consumer. The retained
/// Swift batch loop remains the fallback for every unsupported combination.
enum CSequentialGreyscaleDecoder {
    /// Metadata and lookup owners enclose the synchronous producer and consumer.
    /// The consumer receives only coefficients; it must join all work and
    /// restore the Int32 binding before returning or throwing. No C metadata
    /// pointer may escape this function or enter reconstruction workers.
    @inline(never)
    static func decodeBatchesIfEligible(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
        lookup: ACLookahead?, blocksPerRow: Int, blockRows: Int,
        precision: Int, restartInterval: Int,
        windowBlocks: Int = SequentialGreyscalePlan.maximumBatchBlocks,
        transformGroupBlocks: Int = SequentialGreyscalePlan.maximumBatchBlocks,
        consume: (UnsafeMutableBufferPointer<Int32>, Int) throws -> Void
    ) throws -> Bool {
        guard (precision == 8 || precision == 12), NativeDSP.usesAccelerate else {
            return false
        }
        var handled = false
        try CDCTKernel.withBorrowed(dcTable: dcTable, acTable: acTable, lookup: lookup,
            enabled: true) { kernel in
            guard let kernel else { return }
            // The caller already validates these extents. Retain a local proof
            // for direct internal calls before allocation or pointer arithmetic.
            let (blocks, overflow) = blocksPerRow.multipliedReportingOverflow(by: blockRows)
            let (_, countOverflow) = blocks.multipliedReportingOverflow(by: 64)
            guard blocksPerRow > 0, blockRows > 0, !overflow, !countOverflow,
                  restartInterval >= 0,
                  transformGroupBlocks == 1024 || transformGroupBlocks == 256,
                  windowBlocks > 0,
                  windowBlocks <= SequentialGreyscalePlan.maximumWindowBlocks,
                  windowBlocks >= blocks || windowBlocks % transformGroupBlocks == 0 else {
                throw JLIError.decodingFailed("Invalid sequential coefficient destination")
            }
            // This allocation and every reader access follow successful kernel
            // admission. A nil kernel returns false with no side effects.
            let capacity = min(windowBlocks, blocks) * 64
            var coefficients = [Int32](unsafeUninitializedCapacity: capacity) { _, count in count = capacity }
            var previousDC: Int32 = 0
            var restartIndex = 0
            try coefficients.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else {
                    throw JLIError.decodingFailed("Invalid sequential coefficient destination")
                }
                for first in stride(from: 0, to: blocks, by: windowBlocks) {
                    let end = min(first + windowBlocks, blocks)
                    var index = first
                    while index < end {
                        try NativeOperation.check()
                        let groupEnd = index + transformGroupBlocks - index % transformGroupBlocks
                        let rowEnd = min(end, min(index + blocksPerRow - index % blocksPerRow, groupEnd))
                        while index < rowEnd {
                            if restartInterval > 0, index > 0, index % restartInterval == 0 {
                                try reader.skipRestartMarker(expectedIndex: restartIndex)
                                restartIndex = (restartIndex + 1) & 7
                                previousDC = 0
                            }
                            let spanEnd: Int
                            if restartInterval > 0 {
                                let nextRestart = index + restartInterval - (index % restartInterval)
                                spanEnd = min(rowEnd, nextRestart)
                            } else {
                                spanEnd = rowEnd
                            }
                            let count = spanEnd - index
                            let span = UnsafeMutableBufferPointer(start: base + (index - first) * 64, count: count * 64)
                            try reader.decodeDCTRun(using: kernel, previousDC: &previousDC,
                                precision: precision, blockCount: count, into: span)
                            index = spanEnd
                        }
                    }
                    // Entropy errors throw before publication; a consumer error
                    // also propagates directly, never restarting through Swift.
                    try consume(UnsafeMutableBufferPointer(start: base, count: (end - first) * 64), first)
                }
            }
            handled = true
        }
        return handled
    }
}
