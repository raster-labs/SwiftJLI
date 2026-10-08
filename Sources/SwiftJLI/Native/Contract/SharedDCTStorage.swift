// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Float component planes are algorithm workspace. Source pixels are read from
/// the caller's scoped borrow; RGB conversion scratch is bounded to at most eight rows.
enum SharedDCTStorage {
    static func normalisedByte(_ bytes: UnsafeRawBufferPointer, at p: Int) throws -> Float {
        let bits = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8
            | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
        let sample = Float(bitPattern: bits)
        guard sample.isFinite else { throw CodecError(.invalidArgument, "Float input must contain only finite samples.") }
        return (min(max(sample, 0), 1) * 255).rounded(.toNearestOrAwayFromZero)
    }

    static func read(_ source: BorrowedSamplePlane, width: Int, height: Int,
                     components: Int, precision: Int, normalisedFloatInput: Bool = false,
                     preconvertedYCbCr: Bool = false, greyscaleOutput: Bool = false) throws -> (y: [Float], cb: [Float], cr: [Float]) {
        let count = width * height, bps = normalisedFloatInput ? 4 : precision == 8 ? 1 : 2
        let colourOutput = components > 1 && !greyscaleOutput
        var y = [Float](repeating: 0, count: count)
        var cb = colourOutput ? y : [], cr = colourOutput ? y : []
        var scratch = [Float](repeating: 0, count: width * 3)
        try y.withUnsafeMutableBufferPointer { yp in
            try cb.withUnsafeMutableBufferPointer { cp in
                try cr.withUnsafeMutableBufferPointer { rp in
                    try scratch.withUnsafeMutableBufferPointer { sp in
                        guard let yy = yp.baseAddress, let s = sp.baseAddress else { return }
                        let r = s, g = s + width, b = s + width * 2
                        for row in 0..<height {
                            try NativeOperation.check()
                            let offset = row * source.rowBytes, out = row * width
                            if bps == 1, let bytes = source.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                                if components == 1 { jliDSP_vfltu8(bytes + offset, 1, yy + out, 1, width) }
                                else {
                                    jliDSP_vfltu8(bytes + offset, components, r, 1, width)
                                    jliDSP_vfltu8(bytes + offset + 1, components, g, 1, width)
                                    jliDSP_vfltu8(bytes + offset + 2, components, b, 1, width)
                                }
                            } else {
                                for x in 0..<width {
                                    for c in 0..<(components == 1 ? 1 : 3) {
                                        let p = offset + (x * components + c) * bps
                                        let v: Float
                                        if normalisedFloatInput {
                                            v = try normalisedByte(source.bytes, at: p)
                                        } else {
                                            v = Float(Int(source.bytes[p]) | (Int(source.bytes[p + 1]) << 8))
                                        }
                                        if components == 1 { yy[out + x] = v }
                                        else { s[c * width + x] = v }
                                    }
                                }
                            }
                            if components > 1 {
                                if preconvertedYCbCr {
                                    guard let cc = cp.baseAddress, let rr = rp.baseAddress else {
                                        throw CodecError(.internalFailure, "Preconverted YCbCr requires three output planes.")
                                    }
                                    (yy + out).update(from: r, count: width)
                                    (cc + out).update(from: g, count: width)
                                    (rr + out).update(from: b, count: width)
                                    continue
                                }
                                var center = Float(1 << (precision - 1))
                                func channel(_ dst: UnsafeMutablePointer<Float>, _ a: Float, _ bb: Float, _ c: Float, chroma: Bool) {
                                    var a = a, bb = bb, c = c
                                    jliDSP_vsmul(r, 1, &a, dst, 1, width)
                                    jliDSP_vsma(g, 1, &bb, dst, 1, dst, 1, width)
                                    jliDSP_vsma(b, 1, &c, dst, 1, dst, 1, width)
                                    if chroma { jliDSP_vsadd(dst, 1, &center, dst, 1, width) }
                                }
                                channel(yy + out, 0.299, 0.587, 0.114, chroma: false)
                                if colourOutput, let cc = cp.baseAddress, let rr = rp.baseAddress {
                                    channel(cc + out, -0.168736, -0.331264, 0.5, chroma: true)
                                    channel(rr + out, 0.5, -0.418688, -0.081312, chroma: true)
                                }
                            }
                        }
                    }
                }
            }
        }
        return (y, cb, cr)
    }

    /// Round and interleave reconstructed samples directly into final storage.
    /// Padding is untouched. The Float conversion sequence matches the legacy
    /// DSP path, including ties-to-even for colour and ties-away for greyscale.
    static func write(_ planes: [(data: [Float], width: Int, height: Int)],
                      width: Int, height: Int, precision: Int, floatOutput: Bool = false, xyb: Bool = false,
                      into destination: BorrowedSampleDestination) throws {
        let nc = planes.count, bps = destination.bytesPerSample
        if nc == 1 {
            try writeGreyscale(planes[0], width: width, height: height, precision: precision,
                               floatOutput: floatOutput, into: destination)
            return
        }
        let cb = xyb ? planes[1].data : nc == 3 ? try ChromaSampling.upsample(planes[1].data, width: planes[1].width,
            height: planes[1].height, targetWidth: width, targetHeight: height) : []
        try NativeOperation.check()
        let cr = xyb ? planes[2].data : nc == 3 ? try ChromaSampling.upsample(planes[2].data, width: planes[2].width,
            height: planes[2].height, targetWidth: width, targetHeight: height) : []
        if nc == 3 && !xyb && !floatOutput && bps == 1 {
            try writeRGB8(planes[0], cb: cb, cr: cr, width: width, height: height,
                          precision: precision, into: destination)
            return
        }
        var scratch = [Float](repeating: 0, count: width * 5)
        try planes[0].data.withUnsafeBufferPointer { yp in
            try cb.withUnsafeBufferPointer { cp in
                try cr.withUnsafeBufferPointer { rp in
                    try scratch.withUnsafeMutableBufferPointer { sp in
                        guard let yy = yp.baseAddress, let s = sp.baseAddress else { return }
                        let cbS = s, crS = s + width, r = s + width * 2, g = s + width * 3, b = s + width * 4
                        var negCenter = -Float(1 << (precision - 1))
                        var rCr: Float = 1.402, gCb: Float = -0.344136, gCr: Float = -0.714136, bCb: Float = 1.772
                        var lo: Float = 0, hi = Float((1 << precision) - 1)
                        for row in 0..<height {
                            try NativeOperation.check()
                            let y = yy + row * planes[0].width
                            if xyb {
                                guard nc == 3, !floatOutput || bps == 4, let pp1 = cp.baseAddress, let pp2 = rp.baseAddress else {
                                    throw JLIError.unsupportedJPEGFeature("Unsupported shared XYB output")
                                }
                                for x in 0..<width {
                                    let rgb = ColorConversion.xybSampleToRGB(x: y[x],
                                        y: pp1[row * planes[1].width + x], bChannel: pp2[row * planes[2].width + x])
                                    for c in 0..<3 {
                                        let sample = c == 0 ? rgb.r : c == 1 ? rgb.g : rgb.b
                                        guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite XYB reconstruction") }
                                        let offset = row * destination.rowBytes + (x * 3 + c) * bps
                                        if floatOutput {
                                            let bits = (sample / 255).bitPattern
                                            for byte in 0..<4 { destination.bytes[offset + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
                                        } else {
                                            destination.bytes[offset] = UInt8(clamping: Int(sample.rounded()))
                                            if bps == 2 { destination.bytes[offset + 1] = 0 }
                                        }
                                    }
                                }
                                continue
                            }
                            if floatOutput {
                                guard nc == 1 && bps == 4 else { throw JLIError.unsupportedJPEGFeature("Invalid raw Float32 destination") }
                                for x in 0..<width {
                                    let value = y[x]
                                    guard value.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                                    let bits = value.bitPattern, offset = row * destination.rowBytes + x * 4
                                    for byte in 0..<4 { destination.bytes[offset + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
                                }
                                continue
                            }
                            if nc == 3, let cc = cp.baseAddress, let rr = rp.baseAddress {
                                jliDSP_vsadd(cc + row * width, 1, &negCenter, cbS, 1, width)
                                jliDSP_vsadd(rr + row * width, 1, &negCenter, crS, 1, width)
                                jliDSP_vsma(crS, 1, &rCr, y, 1, r, 1, width)
                                jliDSP_vsmul(cbS, 1, &gCb, g, 1, width)
                                jliDSP_vsma(crS, 1, &gCr, g, 1, g, 1, width)
                                jliDSP_vadd(y, 1, g, 1, g, 1, width)
                                jliDSP_vsma(cbS, 1, &bCb, y, 1, b, 1, width)
                                jliDSP_vclip(r, 1, &lo, &hi, r, 1, width)
                                jliDSP_vclip(g, 1, &lo, &hi, g, 1, width)
                                jliDSP_vclip(b, 1, &lo, &hi, b, 1, width)
                            }
                            if nc == 3 && bps == 1, let bytes = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                                // Finite integer coefficients/tables and bounded
                                // interpolation produce finite, clipped samples.
                                let out = bytes + row * destination.rowBytes
                                jliDSP_vfixru8(r, 1, out, 3, width)
                                jliDSP_vfixru8(g, 1, out + 1, 3, width)
                                jliDSP_vfixru8(b, 1, out + 2, 3, width)
                                continue
                            }
                            for x in 0..<width {
                                for c in 0..<nc {
                                    let sample = nc == 1 ? y[x] : s[(c + 2) * width + x]
                                    guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                                    let value = UInt16(max(0, min(hi, sample)).rounded(nc == 1 ? .toNearestOrAwayFromZero : .toNearestOrEven))
                                    let offset = row * destination.rowBytes + (x * nc + c) * bps
                                    destination.bytes[offset] = UInt8(truncatingIfNeeded: value)
                                    if bps == 2 { destination.bytes[offset + 1] = UInt8(value >> 8) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private static func writeGreyscale(_ plane: (data: [Float], width: Int, height: Int),
                                       width: Int, height: Int, precision: Int, floatOutput: Bool,
                                       into destination: BorrowedSampleDestination) throws {
        let bps = destination.bytesPerSample
        guard floatOutput ? bps == 4 : (bps == 1 && precision <= 8) || bps == 2,
              let bytes = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw JLIError.unsupportedJPEGFeature("Invalid greyscale destination")
        }
        let maximum = Float((1 << precision) - 1)
        try plane.data.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            for row in 0..<height {
                try NativeOperation.check()
                let src = base + row * plane.width, dst = bytes + row * destination.rowBytes
                if floatOutput {
                    for x in 0..<width {
                        let sample = src[x]
                        guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                        let bits = sample.bitPattern
                        for byte in 0..<4 { dst[x * 4 + byte] = UInt8(truncatingIfNeeded: bits >> (byte * 8)) }
                    }
                } else if bps == 2 {
                    for x in 0..<width {
                        let sample = src[x]
                        guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                        let value = UInt16(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                        dst[x * 2] = UInt8(truncatingIfNeeded: value)
                        dst[x * 2 + 1] = UInt8(value >> 8)
                    }
                } else {
                    for x in 0..<width {
                        let sample = src[x]
                        guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite reconstructed sample") }
                        dst[x] = UInt8(max(0, min(maximum, sample)).rounded(.toNearestOrAwayFromZero))
                    }
                }
            }
        }
    }
    /// Joined lanes convert disjoint row ranges with at most eight rows of
    /// scratch per lane. Accelerate converts into contiguous byte planes and
    /// interleaves directly into the final destination, preserving row padding.
    private static func writeRGB8(_ y: (data: [Float], width: Int, height: Int),
                                  cb: [Float], cr: [Float], width: Int, height: Int, precision: Int,
                                  into destination: BorrowedSampleDestination) throws {
        let rowsPerBatch = y.width == width ? min(8, height) : 1
        let batches = (height + rowsPerBatch - 1) / rowsPerBatch
        let lanes = width * height >= 65536 ? min(NativeOperation.workerLimit, batches) : 1
        let batchesPerLane = (batches + lanes - 1) / lanes
        try y.data.withUnsafeBufferPointer { yp in
            try cb.withUnsafeBufferPointer { cp in
                try cr.withUnsafeBufferPointer { rp in
                    guard let yy = yp.baseAddress, let cc = cp.baseAddress, let rr = rp.baseAddress,
                          let bytes = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    let buffers = RGBOutputBuffers(y: yy, cb: cc, cr: rr, output: bytes)
                    let sourceWidth = y.width, rowBytes = destination.rowBytes
                    try NativeOperation.perform(iterations: lanes) { lane in
                        let firstRow = lane * batchesPerLane * rowsPerBatch
                        let endRow = min(height, firstRow + batchesPerLane * rowsPerBatch)
                        guard firstRow < endRow else { return }
                        try writeRGB8Rows(buffers, rows: firstRow..<endRow, rowsPerBatch: rowsPerBatch,
                            sourceWidth: sourceWidth, width: width, rowBytes: rowBytes, precision: precision)
                    }
                }
            }
        }
    }

    /// Sources stay read-only inside the enclosing borrows. Each joined lane
    /// owns its conversion scratch and a disjoint range of destination rows.
    /// No pointer escapes NativeOperation.perform or the caller's storage lease.
    private struct RGBOutputBuffers: @unchecked Sendable {
        let y: UnsafePointer<Float>
        let cb: UnsafePointer<Float>
        let cr: UnsafePointer<Float>
        let output: UnsafeMutablePointer<UInt8>
    }

    private static func writeRGB8Rows(_ buffers: RGBOutputBuffers, rows: Range<Int>, rowsPerBatch: Int,
                                     sourceWidth: Int, width: Int, rowBytes: Int, precision: Int) throws {
        let capacity = width * min(rowsPerBatch, rows.count)
        var scratch = [Float](repeating: 0, count: capacity * 5)
        #if canImport(Accelerate)
        var bytePlanes = [UInt8](repeating: 0, count: NativeDSP.usesAccelerate ? capacity * 3 : 0)
        #endif
        let yy = buffers.y, cc = buffers.cb, rr = buffers.cr, bytes = buffers.output
        try scratch.withUnsafeMutableBufferPointer { sp in
            guard let s = sp.baseAddress else { return }
            let cbS = s, crS = s + capacity, r = s + capacity * 2, g = s + capacity * 3, b = s + capacity * 4
            var negativeCentre = -Float(1 << (precision - 1))
            var rCr: Float = 1.402, gCb: Float = -0.344136, gCr: Float = -0.714136, bCb: Float = 1.772
            var lo: Float = 0, hi = Float((1 << precision) - 1)
            for firstRow in stride(from: rows.lowerBound, to: rows.upperBound, by: rowsPerBatch) {
                try NativeOperation.check()
                let rows = min(rowsPerBatch, rows.upperBound - firstRow), count = rows * width
                let source = yy + firstRow * sourceWidth
                jliDSP_vsadd(cc + firstRow * width, 1, &negativeCentre, cbS, 1, count)
                jliDSP_vsadd(rr + firstRow * width, 1, &negativeCentre, crS, 1, count)
                jliDSP_vsma(crS, 1, &rCr, source, 1, r, 1, count)
                jliDSP_vsmul(cbS, 1, &gCb, g, 1, count)
                jliDSP_vsma(crS, 1, &gCr, g, 1, g, 1, count)
                jliDSP_vadd(source, 1, g, 1, g, 1, count)
                jliDSP_vsma(cbS, 1, &bCb, source, 1, b, 1, count)
                jliDSP_vclip(r, 1, &lo, &hi, r, 1, count)
                jliDSP_vclip(g, 1, &lo, &hi, g, 1, count)
                jliDSP_vclip(b, 1, &lo, &hi, b, 1, count)
                #if canImport(Accelerate)
                if NativeDSP.usesAccelerate {
                    // Contiguous conversion avoids the costly stride-three
                    // vDSP stores. Interleave only this bounded batch directly
                    // into final storage, honouring the caller's row padding.
                    try bytePlanes.withUnsafeMutableBufferPointer { planar in
                        guard let pr = planar.baseAddress else { return }
                        let pg = pr + capacity, pb = pr + capacity * 2
                        jliDSP_vfixru8(r, 1, pr, 1, count)
                        jliDSP_vfixru8(g, 1, pg, 1, count)
                        jliDSP_vfixru8(b, 1, pb, 1, count)
                        var red = vImage_Buffer(data: pr, height: vImagePixelCount(rows),
                            width: vImagePixelCount(width), rowBytes: width)
                        var green = vImage_Buffer(data: pg, height: vImagePixelCount(rows),
                            width: vImagePixelCount(width), rowBytes: width)
                        var blue = vImage_Buffer(data: pb, height: vImagePixelCount(rows),
                            width: vImagePixelCount(width), rowBytes: width)
                        var output = vImage_Buffer(data: bytes + firstRow * rowBytes,
                            height: vImagePixelCount(rows), width: vImagePixelCount(width),
                            rowBytes: rowBytes)
                        let status = vImageConvert_Planar8toRGB888(&red, &green, &blue, &output,
                            vImage_Flags(kvImageDoNotTile))
                        guard status == kvImageNoError else {
                            throw CodecError(.internalFailure, "RGB byte interleave failed.")
                        }
                    }
                    continue
                }
                #endif
                if rowBytes == width * 3 {
                    let out = bytes + firstRow * rowBytes
                    jliDSP_vfixru8(r, 1, out, 3, count)
                    jliDSP_vfixru8(g, 1, out + 1, 3, count)
                    jliDSP_vfixru8(b, 1, out + 2, 3, count)
                } else {
                    for row in 0..<rows {
                        let offset = row * width, out = bytes + (firstRow + row) * rowBytes
                        jliDSP_vfixru8(r + offset, 1, out, 3, width)
                        jliDSP_vfixru8(g + offset, 1, out + 1, 3, width)
                        jliDSP_vfixru8(b + offset, 1, out + 2, 3, width)
                    }
                }
            }
        }
    }

}
