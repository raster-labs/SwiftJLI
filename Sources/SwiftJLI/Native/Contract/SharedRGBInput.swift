// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

extension SharedDCTStorage {
    /// Borrow RGB8 rows directly into the required Y/Cb/Cr algorithm planes.
    /// Lanes own disjoint output rows and at most eight rows of conversion scratch.
    static func readRGB8(_ source: BorrowedSamplePlane, width: Int, height: Int) throws
        -> (y: [Float], cb: [Float], cr: [Float]) {
        let count = width * height
        var y = [Float](repeating: 0, count: count)
        var cb = [Float](repeating: 0, count: count)
        var cr = [Float](repeating: 0, count: count)
        let rowsPerBatch = min(8, height)
        let batches = (height + rowsPerBatch - 1) / rowsPerBatch
        let lanes = count >= 65536 ? min(NativeOperation.workerLimit, batches) : 1
        let batchesPerLane = (batches + lanes - 1) / lanes
        try y.withUnsafeMutableBufferPointer { yp in
            try cb.withUnsafeMutableBufferPointer { cp in
                try cr.withUnsafeMutableBufferPointer { rp in
                    guard let bytes = source.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let yy = yp.baseAddress, let cc = cp.baseAddress, let rr = rp.baseAddress else { return }
                    let buffers = RGBInputBuffers(source: bytes, y: yy, cb: cc, cr: rr)
                    let rowBytes = source.rowBytes
                    try NativeOperation.perform(iterations: lanes) { lane in
                        let firstRow = lane * batchesPerLane * rowsPerBatch
                        let endRow = min(height, firstRow + batchesPerLane * rowsPerBatch)
                        guard firstRow < endRow else { return }
                        try readRGB8Rows(buffers, rows: firstRow..<endRow, rowsPerBatch: rowsPerBatch,
                            width: width, rowBytes: rowBytes)
                    }
                }
            }
        }
        return (y, cb, cr)
    }

    /// The input stays read-only in the caller's borrow. Each joined lane writes
    /// disjoint rows of all three owned output arrays and owns its scratch.
    /// No pointer outlives perform, the mutable array borrows or the source lease.
    private struct RGBInputBuffers: @unchecked Sendable {
        let source: UnsafePointer<UInt8>
        let y: UnsafeMutablePointer<Float>
        let cb: UnsafeMutablePointer<Float>
        let cr: UnsafeMutablePointer<Float>
    }

    private static func readRGB8Rows(_ buffers: RGBInputBuffers, rows: Range<Int>, rowsPerBatch: Int,
                                    width: Int, rowBytes: Int) throws {
        let capacity = width * min(rowsPerBatch, rows.count)
        var scratch = [Float](repeating: 0, count: capacity * 3)
        #if canImport(Accelerate)
        var bytePlanes = [UInt8](repeating: 0, count: NativeDSP.usesAccelerate ? capacity * 3 : 0)
        #endif
        try scratch.withUnsafeMutableBufferPointer { sp in
            guard let r = sp.baseAddress else { return }
            let g = r + capacity, b = r + capacity * 2
            for firstRow in stride(from: rows.lowerBound, to: rows.upperBound, by: rowsPerBatch) {
                try NativeOperation.check()
                let batchRows = min(rowsPerBatch, rows.upperBound - firstRow), count = batchRows * width
                let source = buffers.source + firstRow * rowBytes
                #if canImport(Accelerate)
                if NativeDSP.usesAccelerate {
                    try bytePlanes.withUnsafeMutableBufferPointer { planar in
                        guard let pr = planar.baseAddress else { return }
                        let pg = pr + capacity, pb = pr + capacity * 2
                        var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source),
                            height: vImagePixelCount(batchRows), width: vImagePixelCount(width), rowBytes: rowBytes)
                        var red = vImage_Buffer(data: pr, height: vImagePixelCount(batchRows),
                            width: vImagePixelCount(width), rowBytes: width)
                        var green = vImage_Buffer(data: pg, height: vImagePixelCount(batchRows),
                            width: vImagePixelCount(width), rowBytes: width)
                        var blue = vImage_Buffer(data: pb, height: vImagePixelCount(batchRows),
                            width: vImagePixelCount(width), rowBytes: width)
                        let status = vImageConvert_RGB888toPlanar8(&input, &red, &green, &blue,
                            vImage_Flags(kvImageDoNotTile))
                        guard status == kvImageNoError else {
                            throw CodecError(.internalFailure, "RGB byte deinterleave failed.")
                        }
                        jliDSP_vfltu8(pr, 1, r, 1, count)
                        jliDSP_vfltu8(pg, 1, g, 1, count)
                        jliDSP_vfltu8(pb, 1, b, 1, count)
                    }
                } else {
                    readRGB8ScalarRows(source, rows: batchRows, width: width, rowBytes: rowBytes, r: r, g: g, b: b)
                }
                #else
                readRGB8ScalarRows(source, rows: batchRows, width: width, rowBytes: rowBytes, r: r, g: g, b: b)
                #endif
                let offset = firstRow * width
                var centre: Float = 128
                func channel(_ output: UnsafeMutablePointer<Float>, _ a: Float, _ bb: Float, _ c: Float, chroma: Bool) {
                    var a = a, bb = bb, c = c
                    jliDSP_vsmul(r, 1, &a, output, 1, count)
                    jliDSP_vsma(g, 1, &bb, output, 1, output, 1, count)
                    jliDSP_vsma(b, 1, &c, output, 1, output, 1, count)
                    if chroma { jliDSP_vsadd(output, 1, &centre, output, 1, count) }
                }
                channel(buffers.y + offset, 0.299, 0.587, 0.114, chroma: false)
                channel(buffers.cb + offset, -0.168736, -0.331264, 0.5, chroma: true)
                channel(buffers.cr + offset, 0.5, -0.418688, -0.081312, chroma: true)
            }
        }
    }

    private static func readRGB8ScalarRows(_ source: UnsafePointer<UInt8>, rows: Int, width: Int, rowBytes: Int,
                                         r: UnsafeMutablePointer<Float>, g: UnsafeMutablePointer<Float>, b: UnsafeMutablePointer<Float>) {
        for row in 0..<rows {
            let input = source + row * rowBytes, offset = row * width
            jliDSP_vfltu8(input, 3, r + offset, 1, width)
            jliDSP_vfltu8(input + 1, 3, g + offset, 1, width)
            jliDSP_vfltu8(input + 2, 3, b + offset, 1, width)
        }
    }
}
