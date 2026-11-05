// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
import Foundation
extension QualifiedJPEGDecoder {
    internal static func losslessParametersCore(frame: QualifiedFrameInfo, scans: QualifiedStorageArray<QualifiedScanData>,
                                            configuration: QualifiedJPEGDecoder.Configuration) -> QualifiedLosslessParametersOutcome {
        let precision = frame.precision
        guard (2...16).contains(precision) else {
            return .failure(QualifiedFailure(code: 138, kind: .unsupported, detail0: Int(precision)))
        }
        // Lossless reconstructs exact integer samples; a float32 request here would
        // only be a lossy-looking convenience cast and is rejected so callers get
        // the bit-exact uint path (which already preserves every value exactly).
        guard configuration.outputPixelFormat != .float32 else {
            return .failure(QualifiedFailure(code: 139, kind: .unsupported))
        }
        let w = frame.width, h = frame.height
        guard w >= 1, h >= 1, w <= 65535, h <= 65535 else {
            return .failure(QualifiedFailure(code: 140, kind: .decoding, detail0: Int(w), detail1: Int(h)))
        }
        // Decompression-bomb guard: a tiny SOF can declare dimensions whose product
        // would force a multi-gigabyte plane allocation (an uncatchable OOM trap).
        // Cap total samples before allocating. See `maxDecodablePixels`.
        let (pixels, overflow) = w.multipliedReportingOverflow(by: h)
        guard !overflow, pixels <= QualifiedJPEGDecoder.maxDecodablePixels else {
            return .failure(QualifiedFailure(code: 141, kind: .decoding, detail0: Int(w), detail1: Int(h), detail2: Int(QualifiedJPEGDecoder.maxDecodablePixels)))
        }
        let nc = frame.components.count
        guard nc == 1 || nc == 3 else {
            return .failure(QualifiedFailure(code: 142, kind: .unsupported, detail0: Int(nc)))
        }
        for c in frame.components where c.horizontalSampling != 1 || c.verticalSampling != 1 {
            return .failure(QualifiedFailure(code: 143, kind: .unsupported))
        }
        guard scans.count == 1 else {
            return .failure(QualifiedFailure(code: 144, kind: .unsupported))
        }
        let scan = scans[0]
        guard scan.header.components.count == nc else {
            return .failure(QualifiedFailure(code: 144, kind: .unsupported))
        }
        let predictor = scan.header.spectralStart       // 1–7
        let pt = scan.header.successiveApproxLow         // point transform
        guard (1...7).contains(predictor) else {
            return .failure(QualifiedFailure(code: 145, kind: .decoding, detail0: Int(predictor)))
        }
        // The point transform shifts the initial predictor by `precision-1-pt`; a
        // pt ≥ precision yields a negative shift count, which traps at runtime.
        // T.81 also constrains Pt < P for lossless. Reject out-of-range values
        // (a 4-bit Al field can carry 0–15) with a thrown error, never a trap.
        guard pt >= 0, pt < precision else {
            return .failure(QualifiedFailure(code: 146, kind: .decoding, detail0: Int(pt), detail1: Int(precision)))
        }
        return .success((predictor, pt, scan))
    }
    internal static func losslessScanGrayIntoCore<Table: QualifiedHuffmanDecodeTable, Samples: QualifiedLosslessSampleStorage>(
        _ p: Samples, width w: Int, height h: Int,
        predictor: Int, half: Int32, table: Table, reader: inout QualifiedBitReader, cancellation: QualifiedCancellation = .never
    ) -> QualifiedOutcome<Void> {
        for y in 0..<h {
            if case .failure(let failure) = cancellation.check() { return .failure(failure) }
            let row = y * w, prevRow = row - w
            for x in 0..<w {
                if x & 4095 == 0, case .failure(let failure) = cancellation.check() { return .failure(failure) }
                let px: Int32
                if x == 0 {
                    px = y == 0 ? half : p[prevRow]                    // Rb (or initial)
                } else if y == 0 {
                    px = p[row + x - 1]                                // Ra
                } else {
                    let ra = p[row + x - 1], rb = p[prevRow + x], rc = p[prevRow + x - 1]
                    switch predictor {
                    case 1: px = ra
                    case 2: px = rb
                    case 3: px = rc
                    case 4: px = ra + rb - rc
                    case 5: px = ra + ((rb - rc) >> 1)
                    case 6: px = rb + ((ra - rc) >> 1)
                    default: px = (ra + rb) >> 1                       // 7
                    }
                }
                let coreOutcome1 = QualifiedHuffmanDecoder.decodeSymbolCore(from: &reader, table: table)
                guard case .success(let coreValue1) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
                let cat = Int(coreValue1)
                let diff: Int32
                if cat == 0 { diff = 0 }
                else if cat == 16 { diff = -32768 }                    // T.81 special case
                else {
                    let coreOutcome2 = QualifiedHuffmanDecoder.decodeValueCore(from: &reader, category: cat)
                    guard case .success(let value) = coreOutcome2 else { return .failure(coreOutcome2.failureValue) }
                    diff = value
                }
                p[row + x] = (px + diff) & 0xFFFF
            }
        }
        return .success(())
    }
    internal func validateDecodableCore(_ frame: QualifiedFrameInfo, quantTableCount: Int) -> QualifiedOutcome<Void> {
        // Precision drives the level shift `1 << (precision-1)`, which traps for
        // precision 0; we only decode 8-bit (color/gray) and 12-bit (gray).
        guard frame.precision == 8 || frame.precision == 12 else {
            return .failure(QualifiedFailure(code: 147, kind: .unsupported, detail0: Int(frame.precision)))
        }
        // Dimensions: positive and within the 16-bit SOF field range. Zero width
        // or height would divide by zero when computing the MCU grid.
        guard frame.width >= 1, frame.height >= 1,
              frame.width <= 65535, frame.height <= 65535 else {
            return .failure(QualifiedFailure(code: 148, kind: .decoding, detail0: Int(frame.width), detail1: Int(frame.height)))
        }
        // Decompression-bomb guard: the 16-bit SOF fields permit up to ~4.29e9
        // pixels, whose coefficient/scratch planes would OOM-trap from a ~20-byte
        // header. Reject anything beyond `maxDecodablePixels` before allocating.
        let (pixels, overflow) = frame.width.multipliedReportingOverflow(by: frame.height)
        guard !overflow, pixels <= QualifiedJPEGDecoder.maxDecodablePixels else {
            return .failure(QualifiedFailure(code: 149, kind: .decoding, detail0: Int(frame.width), detail1: Int(frame.height), detail2: Int(QualifiedJPEGDecoder.maxDecodablePixels)))
        }
        // Only grayscale (1) and YCbCr (3) layouts are decodable; the color path
        // assumes exactly three planes (Y, Cb, Cr).
        guard frame.components.count == 1 || frame.components.count == 3 else {
            return .failure(QualifiedFailure(code: 150, kind: .unsupported, detail0: Int(frame.components.count)))
        }
        for comp in frame.components {
            // Sampling factors are 1–4 per T.81; a zero factor zeroes the max and
            // divides by zero in the MCU-grid math.
            guard (1...4).contains(comp.horizontalSampling),
                  (1...4).contains(comp.verticalSampling) else {
                return .failure(QualifiedFailure(code: 151, kind: .decoding, detail0: Int(comp.id)))
            }
            // The component must reference a quant table that was actually defined.
            guard comp.quantTableIndex >= 0, comp.quantTableIndex < quantTableCount else {
                return .failure(QualifiedFailure(code: 152, kind: .decoding, detail0: Int(comp.id), detail1: Int(comp.quantTableIndex)))
            }
        }
        return .success(())
    }
    internal struct ReconstructPtrs {
        let zz: UnsafePointer<Int32>
        let qt: UnsafePointer<Float>
        let px: UnsafeMutablePointer<Float>
        let scratch: UnsafeMutablePointer<Float>
        let plane: UnsafeMutablePointer<Float>
    }
    internal static func reconstructBlocks(
        _ blocks: Range<Int>, ptrs: ReconstructPtrs, blocksH: Int,
        compWidth: Int, compHeight: Int, precision: Int, firstBlockRow: Int = 0,
        tables: QualifiedAccelerateDSP.ReconstructionTables
    ) {
        let m = blocks.count
        guard m > 0 else { return }
        let base = blocks.lowerBound
        let px = ptrs.px + base * 64
        QualifiedAccelerateDSP.inverseDCTBatchDequantized(
            zigzag: ptrs.zz + base * 64, quantTable: ptrs.qt,
            output: px, scratch: ptrs.scratch + base * 64, blockCount: m, tables: tables)

        // Level shift +2^(P-1) + clamp [0, 2^P-1] — 128/255 for 8-bit,
        // 2048/4095 for 12-bit; per-element ops, so chunking changes nothing.
        let center = Float(1 << (precision - 1))
        let hi = Float((1 << precision) - 1)
        for index in 0..<(m * 64) { px[index] = min(max(px[index] + center, 0), hi) }

        for bi in 0..<m {
            let b = base + bi
            let startX = (b % blocksH) * 8
            let startY = (firstBlockRow + b / blocksH) * 8
            // MCU geometry can pad subsampled components past the component's
            // actual extent (e.g. a 4:2:0 luma grid rounded up to even blocks on
            // a tiny image) — such blocks decode but land entirely outside the
            // exact-size plane and must be skipped, never clamped negative.
            guard startX < compWidth, startY < compHeight else { continue }
            let blockBase = bi * 64
            let runW = min(8, compWidth - startX)
            for y in 0..<8 {
                let py = startY + y
                if py >= compHeight { break }
                memcpy(ptrs.plane + py * compWidth + startX,
                       px + blockBase + y * 8,
                       runW * MemoryLayout<Float>.size)
            }
        }
    }
}
