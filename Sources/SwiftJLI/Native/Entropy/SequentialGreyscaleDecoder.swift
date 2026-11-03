// SPDX-License-Identifier: Apache-2.0

/// A one-component scan owns one coefficient plane. Borrow it once for the
/// synchronous scan instead of repeatedly checking nested-array uniqueness for
/// every block. Entropy arithmetic, restart order and row cancellation remain
/// the same as the general interleaved decoder.
enum SequentialGreyscaleDecoder {
    /// Serial scan with bounded coefficient storage. The consumer completes
    /// synchronously before the same slot is reused; its pointer cannot escape.
    /// DC prediction and restart numbering span batches, while each batch keeps
    /// the established 1024-block reconstruction grouping.
    static func decodeBatches(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
        lookup: ACLookahead?, blocksPerRow: Int, blockRows: Int,
        precision: Int, restartInterval: Int,
        consume: (UnsafeBufferPointer<Int32>, Int) throws -> Void
    ) throws {
        let (blocks, overflow) = blocksPerRow.multipliedReportingOverflow(by: blockRows)
        let (_, countOverflow) = blocks.multipliedReportingOverflow(by: 64)
        guard blocksPerRow > 0, blockRows > 0, !overflow, !countOverflow,
              (8...12).contains(precision), restartInterval >= 0 else {
            throw JLIError.decodingFailed("Invalid sequential coefficient destination")
        }
        let capacity = min(1024, blocks) * 64
        var coefficients = [Int32](unsafeUninitializedCapacity: capacity) { _, count in count = capacity }
        var previousDC: Int32 = 0
        var restartIndex = 0
        try coefficients.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            for first in stride(from: 0, to: blocks, by: 1024) {
                let end = min(first + 1024, blocks)
                var index = first
                while index < end {
                    try NativeOperation.check()
                    let rowEnd = min(end, index + blocksPerRow - index % blocksPerRow)
                    while index < rowEnd {
                        if restartInterval > 0, index > 0, index % restartInterval == 0 {
                            try reader.skipRestartMarker(expectedIndex: restartIndex)
                            restartIndex = (restartIndex + 1) & 7
                            previousDC = 0
                        }
                        let difference = try HuffmanDecoder.decodeDC(from: &reader, table: dcTable)
                        let dc = Int64(previousDC) + Int64(difference)
                        guard abs(dc) <= (1 << (precision + 2)) else {
                            throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
                        }
                        previousDC = Int32(dc)
                        let block = UnsafeMutableBufferPointer(start: base + (index - first) * 64, count: 64)
                        if let lookup {
                            try HuffmanDecoder.decodeAC(from: &reader, table: acTable, lookup: lookup, into: block)
                        } else {
                            try HuffmanDecoder.decodeAC(from: &reader, table: acTable, into: block)
                        }
                        block[0] = previousDC
                        index += 1
                    }
                }
                try consume(UnsafeBufferPointer(start: base, count: (end - first) * 64), first)
            }
        }
    }

    static func decode(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
        lookup: ACLookahead?, coefficients: UnsafeMutableBufferPointer<Int32>,
        blocksPerRow: Int, blockRows: Int, precision: Int, restartInterval: Int
    ) throws {
        let (blocks, blockOverflow) = blocksPerRow.multipliedReportingOverflow(by: blockRows)
        let (required, countOverflow) = blocks.multipliedReportingOverflow(by: 64)
        guard blocksPerRow > 0, blockRows > 0, !blockOverflow, !countOverflow,
              required <= coefficients.count, (8...12).contains(precision),
              restartInterval >= 0, let base = coefficients.baseAddress else {
            throw JLIError.decodingFailed("Invalid sequential coefficient destination")
        }
        var previousDC: Int32 = 0
        var restartIndex = 0
        for y in 0..<blockRows {
            try NativeOperation.check()
            for x in 0..<blocksPerRow {
                let index = y * blocksPerRow + x
                if restartInterval > 0, index > 0, index % restartInterval == 0 {
                    try reader.skipRestartMarker(expectedIndex: restartIndex)
                    restartIndex = (restartIndex + 1) & 7
                    previousDC = 0
                }
                let difference = try HuffmanDecoder.decodeDC(from: &reader, table: dcTable)
                let dc = Int64(previousDC) + Int64(difference)
                guard abs(dc) <= (1 << (precision + 2)) else {
                    throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
                }
                previousDC = Int32(dc)
                let block = UnsafeMutableBufferPointer(start: base + index * 64, count: 64)
                if let lookup {
                    try HuffmanDecoder.decodeAC(from: &reader, table: acTable, lookup: lookup, into: block)
                } else {
                    try HuffmanDecoder.decodeAC(from: &reader, table: acTable, into: block)
                }
                block[0] = previousDC
            }
        }
    }
}
