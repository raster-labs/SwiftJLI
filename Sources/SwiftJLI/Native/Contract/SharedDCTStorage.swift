// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Float component planes are algorithm workspace. Source pixels are read from
/// the caller's scoped borrow; only a row of RGB conversion scratch is needed.
enum SharedDCTStorage {
    static func normalisedByte(_ bytes: UnsafeRawBufferPointer, at p: Int) throws -> Float {
        let bits = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8
            | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
        let sample = Float(bitPattern: bits)
        guard sample.isFinite else { throw CodecError(.invalidArgument, "Float input must contain only finite samples.") }
        return (min(max(sample, 0), 1) * 255).rounded(.toNearestOrAwayFromZero)
    }

    static func read(_ source: BorrowedSamplePlane, width: Int, height: Int,
                     components: Int, precision: Int, normalisedFloatInput: Bool = false) throws -> (y: [Float], cb: [Float], cr: [Float]) {
        let count = width * height, bps = normalisedFloatInput ? 4 : precision == 8 ? 1 : 2
        var y = [Float](repeating: 0, count: count)
        var cb = components == 3 ? y : [], cr = components == 3 ? y : []
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
                                    jliDSP_vfltu8(bytes + offset, 3, r, 1, width)
                                    jliDSP_vfltu8(bytes + offset + 1, 3, g, 1, width)
                                    jliDSP_vfltu8(bytes + offset + 2, 3, b, 1, width)
                                }
                            } else {
                                for x in 0..<width {
                                    for c in 0..<components {
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
                            if components == 3, let cc = cp.baseAddress, let rr = rp.baseAddress {
                                var center = Float(1 << (precision - 1))
                                func channel(_ dst: UnsafeMutablePointer<Float>, _ a: Float, _ bb: Float, _ c: Float, chroma: Bool) {
                                    var a = a, bb = bb, c = c
                                    jliDSP_vsmul(r, 1, &a, dst, 1, width)
                                    jliDSP_vsma(g, 1, &bb, dst, 1, dst, 1, width)
                                    jliDSP_vsma(b, 1, &c, dst, 1, dst, 1, width)
                                    if chroma { jliDSP_vsadd(dst, 1, &center, dst, 1, width) }
                                }
                                channel(yy + out, 0.299, 0.587, 0.114, chroma: false)
                                channel(cc + out, -0.168736, -0.331264, 0.5, chroma: true)
                                channel(rr + out, 0.5, -0.418688, -0.081312, chroma: true)
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
        let cb = xyb ? planes[1].data : nc == 3 ? try ChromaSampling.upsample(planes[1].data, width: planes[1].width,
            height: planes[1].height, targetWidth: width, targetHeight: height) : []
        try NativeOperation.check()
        let cr = xyb ? planes[2].data : nc == 3 ? try ChromaSampling.upsample(planes[2].data, width: planes[2].width,
            height: planes[2].height, targetWidth: width, targetHeight: height) : []
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
                                guard nc == 3, !floatOutput, let pp1 = cp.baseAddress, let pp2 = rp.baseAddress else {
                                    throw JLIError.unsupportedJPEGFeature("Unsupported shared XYB output")
                                }
                                for x in 0..<width {
                                    let rgb = ColorConversion.xybSampleToRGB(x: y[x],
                                        y: pp1[row * planes[1].width + x], bChannel: pp2[row * planes[2].width + x])
                                    for c in 0..<3 {
                                        let sample = c == 0 ? rgb.r : c == 1 ? rgb.g : rgb.b
                                        guard sample.isFinite else { throw JLIError.decodingFailed("Non-finite XYB reconstruction") }
                                        let value = UInt8(clamping: Int(sample.rounded()))
                                        let offset = row * destination.rowBytes + (x * 3 + c) * bps
                                        destination.bytes[offset] = value
                                        if bps == 2 { destination.bytes[offset + 1] = 0 }
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
}
