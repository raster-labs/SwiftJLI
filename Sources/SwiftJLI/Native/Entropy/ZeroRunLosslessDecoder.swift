// SPDX-License-Identifier: Apache-2.0

/// Predictor 1 with a one-bit zero category can emit a run of equal samples
/// from consecutive zero bits. Other differences use the ordinary entropy
/// arithmetic. The caller retains the destination for this synchronous scope;
/// no pointer escapes and no image-sized scratch allocation is required.
enum ZeroRunLosslessDecoder {
    @inline(never)
    static func decode(
        into destination: BorrowedSampleDestination, width: Int, height: Int,
        half: Int32, table: HuffmanTable, reader: inout BitReader,
        pointTransform: Int, segmentRows: Int
    ) throws {
        let bps = destination.bytesPerSample
        guard width > 0, height > 0, bps == 1 || bps == 2 else {
            throw JLIError.decodingFailed("Invalid zero-run lossless dimensions")
        }
        let (active, overflow1) = width.multipliedReportingOverflow(by: bps)
        let (rowOffset, overflow2) = (height - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (required, overflow3) = rowOffset.addingReportingOverflow(active)
        guard !overflow1, !overflow2, !overflow3,
              destination.rowBytes >= active, required <= destination.bytes.count,
              (0...15).contains(pointTransform), segmentRows > 0,
              (0...65535).contains(half),
              table.lookaheadLength[0] == 1, table.lookaheadSymbol[0] == 0,
              let output = destination.bytes.baseAddress else {
            throw JLIError.decodingFailed("Invalid zero-run lossless destination")
        }
        var firstSample = half
        for y in 0..<height {
            try NativeOperation.check()
            let segmentY = y % segmentRows
            if y > 0, segmentY == 0 {
                try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
            }
            var value = segmentY == 0 ? half : firstSample
            let row = output + y * destination.rowBytes
            var sample16 = UInt16(clamping: Int(value) << pointTransform).littleEndian
            var word64 = UInt64(sample16) * 0x0001_0001_0001_0001
            var sample8 = UInt8(clamping: Int(value) << pointTransform)
            var x = 0
            while x < width {
                let run = reader.consumeZeroBits(maximum: width - x)
                if run > 0 {
                    if x == 0 { firstSample = value }
                    if bps == 1 {
                        (row + x).assumingMemoryBound(to: UInt8.self).update(repeating: sample8, count: run)
                    } else {
                        var written = 0
                        while written + 16 <= run {
                            let baseOffset = (x + written) * 2
                            row.storeBytes(of: word64, toByteOffset: baseOffset, as: UInt64.self)
                            row.storeBytes(of: word64, toByteOffset: baseOffset + 8, as: UInt64.self)
                            row.storeBytes(of: word64, toByteOffset: baseOffset + 16, as: UInt64.self)
                            row.storeBytes(of: word64, toByteOffset: baseOffset + 24, as: UInt64.self)
                            written += 16
                        }
                        while written + 4 <= run {
                            row.storeBytes(of: word64, toByteOffset: (x + written) * 2, as: UInt64.self)
                            written += 4
                        }
                        while written < run {
                            row.storeBytes(of: sample16, toByteOffset: (x + written) * 2, as: UInt16.self)
                            written += 1
                        }
                    }
                    x += run
                } else {
                    let difference: Int32
                    if let fast = reader.fastDecodeLosslessDifference(table) { difference = fast }
                    else {
                        let category = Int(try HuffmanDecoder.decodeSymbol(from: &reader, table: table))
                        difference = category == 0 ? 0 : category == 16 ? -32768
                            : try HuffmanDecoder.decodeValue(from: &reader, category: category)
                    }
                    value = (value + difference) & 0xFFFF
                    if x == 0 { firstSample = value }
                    if bps == 1 {
                        sample8 = UInt8(clamping: Int(value) << pointTransform)
                        row.storeBytes(of: sample8, toByteOffset: x, as: UInt8.self)
                    } else {
                        sample16 = UInt16(clamping: Int(value) << pointTransform).littleEndian
                        word64 = UInt64(sample16) * 0x0001_0001_0001_0001
                        row.storeBytes(of: sample16, toByteOffset: x * 2, as: UInt16.self)
                    }
                    x += 1
                }
            }
        }
    }
}
