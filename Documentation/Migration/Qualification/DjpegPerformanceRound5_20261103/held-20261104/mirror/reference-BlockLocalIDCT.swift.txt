// SPDX-License-Identifier: Apache-2.0

/// A block-local form of the accelerated ARM64 matrix transform. Both matrix
/// passes retain the established ascending, fused multiply-add order. The
/// dequantised input is held in eight local SIMD values, so no image-sized
/// transposition or Float scratch allocation is needed.
enum BlockLocalIDCT {
    static var available: Bool {
        #if canImport(Accelerate) && arch(arm64)
        true
        #else
        false
        #endif
    }

    @inline(__always)
    private static func dot(_ a: SIMD8<Float>, _ b0: SIMD8<Float>, _ b1: SIMD8<Float>,
                            _ b2: SIMD8<Float>, _ b3: SIMD8<Float>, _ b4: SIMD8<Float>,
                            _ b5: SIMD8<Float>, _ b6: SIMD8<Float>, _ b7: SIMD8<Float>) -> SIMD8<Float> {
        var result = SIMD8<Float>(repeating: 0)
        result = result.addingProduct(SIMD8(repeating: a[0]), b0)
        result = result.addingProduct(SIMD8(repeating: a[1]), b1)
        result = result.addingProduct(SIMD8(repeating: a[2]), b2)
        result = result.addingProduct(SIMD8(repeating: a[3]), b3)
        result = result.addingProduct(SIMD8(repeating: a[4]), b4)
        result = result.addingProduct(SIMD8(repeating: a[5]), b5)
        result = result.addingProduct(SIMD8(repeating: a[6]), b6)
        result = result.addingProduct(SIMD8(repeating: a[7]), b7)
        return result
    }

    @inline(__always)
    private static func load(_ pointer: UnsafePointer<Float>, row: Int) -> SIMD8<Float> {
        UnsafeRawPointer(pointer + row * 8).loadUnaligned(as: SIMD8<Float>.self)
    }

    @inline(__always)
    private static func dequantise(_ coefficients: UnsafePointer<Int32>,
                                   _ quantiser: UnsafePointer<Float>,
                                   _ inverseZigzag: UnsafePointer<Int>, row: Int) -> SIMD8<Float> {
        let z = inverseZigzag + row * 8
        let values = SIMD8<Float>(Float(coefficients[z[0]]), Float(coefficients[z[1]]),
                                  Float(coefficients[z[2]]), Float(coefficients[z[3]]),
                                  Float(coefficients[z[4]]), Float(coefficients[z[5]]),
                                  Float(coefficients[z[6]]), Float(coefficients[z[7]]))
        return values * load(quantiser, row: row)
    }

    /// Every Int32 coefficient is consumed into local values before the same
    /// 64-element region is temporarily rebound to Float. No input pointer is
    /// read during that binding; it is restored before returning. Quantiser,
    /// permutation and matrices are separate immutable borrows. The caller
    /// must retain each owner and exclusively own this coefficient block.
    private static func reconstructBlock(_ coefficients: UnsafeMutablePointer<Int32>,
                                         quantiser: UnsafePointer<Float>, inverseZigzag: UnsafePointer<Int>,
                                         matrix: UnsafePointer<Float>, transposed: UnsafePointer<Float>,
                                         precision: Int) {
        let r0 = dequantise(coefficients, quantiser, inverseZigzag, row: 0)
        let r1 = dequantise(coefficients, quantiser, inverseZigzag, row: 1)
        let r2 = dequantise(coefficients, quantiser, inverseZigzag, row: 2)
        let r3 = dequantise(coefficients, quantiser, inverseZigzag, row: 3)
        let r4 = dequantise(coefficients, quantiser, inverseZigzag, row: 4)
        let r5 = dequantise(coefficients, quantiser, inverseZigzag, row: 5)
        let r6 = dequantise(coefficients, quantiser, inverseZigzag, row: 6)
        let r7 = dequantise(coefficients, quantiser, inverseZigzag, row: 7)
        coefficients.withMemoryRebound(to: Float.self, capacity: 64) { output in
            // All coefficients have been consumed into r0...r7 before this
            // binding starts. Retain the first pass in the same block so its
            // inputs and the second-pass matrix need not be live together.
            for row in 0..<8 {
                let first = dot(load(transposed, row: row), r0, r1, r2, r3, r4, r5, r6, r7)
                withUnsafeBytes(of: first) { bytes in
                    UnsafeMutableRawBufferPointer(start: output + row * 8,
                        count: 8 * MemoryLayout<Float>.stride).copyMemory(from: bytes)
                }
            }
            let c0 = load(matrix, row: 0), c1 = load(matrix, row: 1)
            let c2 = load(matrix, row: 2), c3 = load(matrix, row: 3)
            let c4 = load(matrix, row: 4), c5 = load(matrix, row: 5)
            let c6 = load(matrix, row: 6), c7 = load(matrix, row: 7)
            let centre = SIMD8<Float>(repeating: Float(1 << (precision - 1)))
            let maximum = SIMD8<Float>(repeating: Float((1 << precision) - 1))
            let zero = SIMD8<Float>(repeating: 0)
            for row in 0..<8 {
                // A complete row is loaded before replacing that same row;
                // the second pass does not read any other intermediate row.
                let first = load(UnsafePointer(output), row: row)
                var value = dot(first, c0, c1, c2, c3, c4, c5, c6, c7) + centre
                // Comparison masks leave NaN unchanged so the established
                // finite-sample guard still rejects it before publication.
                value = value.replacing(with: zero, where: value .< zero)
                value = value.replacing(with: maximum, where: value .> maximum)
                withUnsafeBytes(of: value) { bytes in
                    UnsafeMutableRawBufferPointer(start: output + row * 8,
                        count: 8 * MemoryLayout<Float>.stride).copyMemory(from: bytes)
                }
            }
        }
    }

    /// Leaves centred, clipped Float bits in consumed coefficient storage.
    /// The caller may subsequently rebind it to Float for sample compaction;
    /// no old Int32 coefficient may be read after this method returns.
    static func reconstruct(_ coefficients: UnsafeMutableBufferPointer<Int32>,
                            quantiser: UnsafeBufferPointer<Float>, precision: Int) throws {
        guard available, NativeDSP.usesAccelerate,
              precision == 8 || precision == 12,
              !coefficients.isEmpty, coefficients.count % 64 == 0,
              coefficients.count <= SequentialGreyscalePlan.maximumWindowBlocks * 64,
              quantiser.count >= 64,
              let base = coefficients.baseAddress, let qt = quantiser.baseAddress else {
            throw JLIError.decodingFailed("Invalid block-local IDCT window")
        }
        try Quantization.inverseZigzagOrder.withUnsafeBufferPointer { indices in
            try AccelerateDSP.dctMatrix.withUnsafeBufferPointer { matrix in
                try AccelerateDSP.dctMatrixTransposed.withUnsafeBufferPointer { transposed in
                    // These positive fixed-size arrays prove all three bases.
                    for block in 0..<(coefficients.count / 64) {
                        if block & 63 == 0 { try NativeOperation.check() }
                        reconstructBlock(base + block * 64, quantiser: qt,
                            inverseZigzag: indices.baseAddress!, matrix: matrix.baseAddress!,
                            transposed: transposed.baseAddress!, precision: precision)
                    }
                }
            }
        }
    }
}
