// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
import Foundation
enum QualifiedAccelerateDSP {
    static func fillDCTMatrix(_ matrix: UnsafeMutableBufferPointer<Float>) {
        precondition(matrix.count == 64)
        for u in 0..<8 {
            let alpha: Float = u == 0 ? 1.0 / sqrt(8.0) : sqrt(2.0 / 8.0)
            for n in 0..<8 {
                matrix[u * 8 + n] = alpha * cos(Float(2 * n + 1) * Float(u) * .pi / 16.0)
            }
        }
    }
    static func fillDCTTranspose(_ matrix: UnsafeBufferPointer<Float>,
                                 into transposed: UnsafeMutableBufferPointer<Float>) {
        precondition(matrix.count == 64 && transposed.count == 64)
        for i in 0..<8 {
            for j in 0..<8 {
                transposed[j * 8 + i] = matrix[i * 8 + j]
            }
        }
    }
    struct ReconstructionTables {
        let dct: UnsafePointer<Float>
        let transposedDCT: UnsafePointer<Float>
        let zigzag: UnsafePointer<Int>
        let inverseZigzag: UnsafePointer<Int>
    }
    static func inverseDCTBatchDequantized(
        zigzag: UnsafePointer<Int32>, quantTable qt: UnsafePointer<Float>,
        output: UnsafeMutablePointer<Float>, scratch: UnsafeMutablePointer<Float>,
        blockCount n: Int, tables: ReconstructionTables
    ) {
        guard n > 0 else { return }
        let rowStride = 8 * n

        // Fused pack: M[r·8N + 8i + c] = dequant(zigzag coefficient at natural
        // position 8r+c) — replaces inverse-zigzag scatter + dequant sweep + pack
        // memcpy with one pass.
        for i in 0..<n {
            let src = zigzag + 64 * i
            for r in 0..<8 {
                let dst = scratch + r * rowStride + 8 * i
                let qrow = qt + 8 * r
                let zrow = tables.inverseZigzag + 8 * r
                for c in 0..<8 {
                    dst[c] = Float(src[zrow[c]]) * qrow[c]
                }
            }
        }

        // Pass 1: T = Cᵀ · M (8 × 8N).
        for row in 0..<8 {
            for block in 0..<n {
                var sum = SIMD8<Float>(repeating: 0)
                for k in 0..<8 {
                    let source = load8(scratch + k * rowStride + block * 8)
                    sum = sum.addingProduct(SIMD8(repeating: tables.transposedDCT[row * 8 + k]), source)
                }
                store8(sum, to: output + row * rowStride + block * 8)
            }
        }

        // Rearrange T → V (8N × 8 per-block-contig).
        for i in 0..<n {
            for r in 0..<8 {
                memcpy(scratch + 64 * i + 8 * r,
                       output + r * rowStride + 8 * i,
                       8 * MemoryLayout<Float>.size)
            }
        }

        // Pass 2: f = V · C (8N × 8). Output per-block-contig.
        for row in 0..<(8 * n) {
            var sum = SIMD8<Float>(repeating: 0)
            for k in 0..<8 {
                sum = sum.addingProduct(SIMD8(repeating: scratch[row * 8 + k]), load8(tables.dct + k * 8))
            }
            store8(sum, to: output + row * 8)
        }
    }
    @inline(__always) private static func load8(_ p: UnsafePointer<Float>) -> SIMD8<Float> {
        SIMD8(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7])
    }
    @inline(__always) private static func store8(_ value: SIMD8<Float>, to p: UnsafeMutablePointer<Float>) {
        p[0] = value[0]; p[1] = value[1]; p[2] = value[2]; p[3] = value[3]
        p[4] = value[4]; p[5] = value[5]; p[6] = value[6]; p[7] = value[7]
    }
    static func imageYCbCrToRGB(y yb: UnsafePointer<Float>, cb cbb: UnsafePointer<Float>,
        cr crb: UnsafePointer<Float>, pixelCount: Int, scratch: UnsafeMutablePointer<Float>,
        planes: UnsafeMutablePointer<UInt8>, output: UnsafeMutableRawPointer) {
        let cbS = scratch, crS = scratch + pixelCount, r = scratch + pixelCount * 2
        let g = scratch + pixelCount * 3, b = scratch + pixelCount * 4
        for i in 0..<pixelCount { cbS[i] = cbb[i] - 128; crS[i] = crb[i] - 128 }
        for i in 0..<pixelCount {
            r[i] = yb[i].addingProduct(1.402, crS[i])
            let green = cbS[i] * -0.344136
            g[i] = green.addingProduct(-0.714136, crS[i]) + yb[i]
            b[i] = yb[i].addingProduct(1.772, cbS[i])
        }
        let pr = planes, pg = pr + pixelCount, pb = pr + pixelCount * 2
        for i in 0..<pixelCount {
            pr[i] = UInt8(min(max(r[i], 0), 255).rounded(.toNearestOrEven))
            pg[i] = UInt8(min(max(g[i], 0), 255).rounded(.toNearestOrEven))
            pb[i] = UInt8(min(max(b[i], 0), 255).rounded(.toNearestOrEven))
        }
        let dst = output.assumingMemoryBound(to: UInt8.self)
        for i in 0..<pixelCount { dst[i * 3] = pr[i]; dst[i * 3 + 1] = pg[i]; dst[i * 3 + 2] = pb[i] }
    }
}
