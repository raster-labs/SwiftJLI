// SPDX-License-Identifier: Apache-2.0

/// A scan-local AC table containing only zero magnitude categories proves that
/// every block has zero AC coefficients. Keep only its DC value; the ordinary
/// coefficient decoder and its fully initialised callback contract are unchanged.
enum DCOnlyGreyscaleDecoder {
    static func accepts(_ table: HuffmanTable) -> Bool {
        !table.values.isEmpty && table.values.allSatisfy { $0 & 0x0F == 0 }
    }

    /// The consumer finishes synchronously before the DC storage is reused. It
    /// must not let the pointer escape or use it concurrently. It may overwrite
    /// consumed values; every slot in the following batch is assigned before
    /// publication. An entropy failure publishes no partial batch.
    static func decodeBatches(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
        blocksPerRow: Int, blockRows: Int, precision: Int, restartInterval: Int,
        consume: (UnsafeMutableBufferPointer<Int32>, Int) throws -> Void
    ) throws {
        let (blocks, overflow) = blocksPerRow.multipliedReportingOverflow(by: blockRows)
        let (_, countOverflow) = blocks.multipliedReportingOverflow(by: 64)
        guard blocksPerRow > 0, blockRows > 0, !overflow, !countOverflow,
              (8...12).contains(precision), restartInterval >= 0, accepts(acTable) else {
            throw JLIError.decodingFailed("Invalid compact DC-only scan")
        }
        let capacity = min(SequentialGreyscalePlan.maximumBatchBlocks, blocks)
        var values = [Int32](unsafeUninitializedCapacity: capacity) { _, count in count = capacity }
        var previousDC: Int32 = 0
        var restartIndex = 0
        try values.withUnsafeMutableBufferPointer { buffer in
            for first in stride(from: 0, to: blocks, by: SequentialGreyscalePlan.maximumBatchBlocks) {
                let end = min(first + SequentialGreyscalePlan.maximumBatchBlocks, blocks)
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
                        // Preserve the ordinary decoder's handling of all zero
                        // categories, including unusual run/zero symbols and a
                        // run reaching beyond the last coefficient. No magnitude
                        // bits follow any symbol admitted by accepts(_:).
                        var coefficient = 1
                        while coefficient < 64 {
                            let symbol = try HuffmanDecoder.decodeSymbol(from: &reader, table: acTable)
                            if symbol == 0 { break }
                            if symbol == 0xF0 { coefficient += 16; continue }
                            coefficient += Int(symbol >> 4)
                            guard coefficient < 64 else { break }
                            coefficient += 1
                        }
                        buffer[index - first] = previousDC
                        index += 1
                    }
                }
                try consume(.init(start: buffer.baseAddress, count: end - first), first)
            }
        }
    }

    /// The quantiser is a validated positive JPEG integer. Preserve the same
    /// two separately rounded Float multiplications as the generic matrix IDCT.
    /// `dc` and `output` hold blockCount disjoint, correctly bound elements.
    static func reconstruct(_ dc: UnsafePointer<Int32>, quantiser: Float,
                            into output: UnsafeMutablePointer<Float>, blockCount: Int) {
        guard blockCount > 0 else { return }
        let basis = AccelerateDSP.dctMatrix[0]
        for block in 0..<blockCount {
            let dequantised = Float(dc[block]) * quantiser
            let firstPass = dequantised * basis
            output[block] = firstPass * basis
        }
    }

    /// Destination validation precedes this call. All entropy, reconstruction
    /// and caller-output work is synchronous on the calling thread. The only
    /// batches are one Int32 and one Float per block, bounded by 1024 blocks.
    static func decodeInto(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
        quantiser: Float, plan: SequentialGreyscalePlan,
        width: Int, height: Int, precision: Int, restartInterval: Int,
        floatOutput: Bool, destination: BorrowedSampleDestination
    ) throws {
        var values = [Float](unsafeUninitializedCapacity: plan.batchBlocks) { _, count in count = plan.batchBlocks }
        try values.withUnsafeMutableBufferPointer { output in
            try decodeBatches(reader: &reader, dcTable: dcTable, acTable: acTable,
                blocksPerRow: plan.blocksPerRow, blockRows: plan.blockRows,
                precision: precision, restartInterval: restartInterval) { dc, first in
                reconstruct(UnsafePointer(dc.baseAddress!), quantiser: quantiser,
                    into: output.baseAddress!, blockCount: dc.count)
                var center = Float(1 << (precision - 1))
                var low: Float = 0, high = Float((1 << precision) - 1)
                jliDSP_vsadd(output.baseAddress!, 1, &center, output.baseAddress!, 1, dc.count)
                jliDSP_vclip(output.baseAddress!, 1, &low, &high, output.baseAddress!, 1, dc.count)
                try SharedDCTStorage.writeGreyscaleConstantBlocks(
                    .init(start: output.baseAddress, count: dc.count), firstBlock: first,
                    blocksPerRow: plan.blocksPerRow, width: width, height: height,
                    precision: precision, floatOutput: floatOutput, into: destination)
            }
        }
    }
}
