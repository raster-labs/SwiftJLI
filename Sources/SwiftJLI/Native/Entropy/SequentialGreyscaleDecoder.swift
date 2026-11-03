// SPDX-License-Identifier: Apache-2.0

/// A one-component scan owns one coefficient plane. Borrow it once for the
/// synchronous scan instead of repeatedly checking nested-array uniqueness for
/// every block. Entropy arithmetic, restart order and row cancellation remain
/// the same as the general interleaved decoder.
enum SequentialGreyscaleDecoder {
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
