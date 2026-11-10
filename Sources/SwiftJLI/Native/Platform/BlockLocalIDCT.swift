// SPDX-License-Identifier: Apache-2.0

/// A block-local form of the accelerated ARM64 matrix transform. Both matrix
/// passes retain the established ascending, fused multiply-add order. The
/// dequantised input is held in eight local SIMD values, so no image-sized
/// transposition or Float scratch allocation is needed.
enum BlockLocalIDCT {
    static var available: Bool {
        #if canImport(Accelerate) && os(macOS) && arch(arm64)
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
    private static func store(_ value: SIMD8<Float>, into pointer: UnsafeMutablePointer<Float>, row: Int) {
        UnsafeMutableRawPointer(pointer + row * 8).storeBytes(of: value, as: SIMD8<Float>.self)
    }

    @inline(__always)
    private static func dequantise(
        _ c: UnsafePointer<Int32>, _ quantiser: UnsafePointer<Float>, row: Int,
        _ i0: Int, _ i1: Int, _ i2: Int, _ i3: Int,
        _ i4: Int, _ i5: Int, _ i6: Int, _ i7: Int
    ) -> SIMD8<Float> {
        let raw = SIMD8<Int32>(c[i0], c[i1], c[i2], c[i3], c[i4], c[i5], c[i6], c[i7])
        return SIMD8<Float>(raw) * load(quantiser, row: row)
    }

    /// Every Int32 coefficient is consumed into local values before the same
    /// 64-element region is temporarily rebound to Float. No input pointer is
    /// read during that binding; it is restored before returning. Quantiser
    /// and matrices are separate immutable borrows. The caller must retain
    /// each owner and exclusively own this coefficient block.
    @inline(__always)
    private static func reconstructBlock(_ coefficients: UnsafeMutablePointer<Int32>,
                                         quantiser: UnsafePointer<Float>,
                                         matrix: UnsafePointer<Float>, transposed: UnsafePointer<Float>,
                                         centre: SIMD8<Float>, maximum: SIMD8<Float>, zero: SIMD8<Float>) {
        let r0 = dequantise(coefficients, quantiser, row: 0,  0,  1,  5,  6, 14, 15, 27, 28)
        let r1 = dequantise(coefficients, quantiser, row: 1,  2,  4,  7, 13, 16, 26, 29, 42)
        let r2 = dequantise(coefficients, quantiser, row: 2,  3,  8, 12, 17, 25, 30, 41, 43)
        let r3 = dequantise(coefficients, quantiser, row: 3,  9, 11, 18, 24, 31, 40, 44, 53)
        let r4 = dequantise(coefficients, quantiser, row: 4, 10, 19, 23, 32, 39, 45, 52, 54)
        let r5 = dequantise(coefficients, quantiser, row: 5, 20, 22, 33, 38, 46, 51, 55, 60)
        let r6 = dequantise(coefficients, quantiser, row: 6, 21, 34, 37, 47, 50, 56, 59, 61)
        let r7 = dequantise(coefficients, quantiser, row: 7, 35, 36, 48, 49, 57, 58, 62, 63)
        coefficients.withMemoryRebound(to: Float.self, capacity: 64) { output in
            // All coefficients have been consumed into r0...r7 before this
            // binding starts. Retain the first pass in the same block so its
            // inputs and the second-pass matrix need not be live together.
            for row in 0..<8 {
                let first = dot(load(transposed, row: row), r0, r1, r2, r3, r4, r5, r6, r7)
                store(first, into: output, row: row)
            }
            let c0 = load(matrix, row: 0), c1 = load(matrix, row: 1)
            let c2 = load(matrix, row: 2), c3 = load(matrix, row: 3)
            let c4 = load(matrix, row: 4), c5 = load(matrix, row: 5)
            let c6 = load(matrix, row: 6), c7 = load(matrix, row: 7)
            for row in 0..<8 {
                // A complete row is loaded before replacing that same row;
                // the second pass does not read any other intermediate row.
                let first = load(UnsafePointer(output), row: row)
                var value = dot(first, c0, c1, c2, c3, c4, c5, c6, c7) + centre
                // Comparison masks leave NaN unchanged so the established
                // finite-sample guard still rejects it before publication.
                value = value.replacing(with: zero, where: value .< zero)
                value = value.replacing(with: maximum, where: value .> maximum)
                store(value, into: output, row: row)
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
        let centre = SIMD8<Float>(repeating: Float(1 << (precision - 1)))
        let maximum = SIMD8<Float>(repeating: Float((1 << precision) - 1))
        let zero = SIMD8<Float>(repeating: 0)
        try AccelerateDSP.dctMatrix.withUnsafeBufferPointer { matrix in
            try AccelerateDSP.dctMatrixTransposed.withUnsafeBufferPointer { transposed in
                // These positive fixed-size arrays prove both bases.
                let mBase = matrix.baseAddress!
                let tBase = transposed.baseAddress!
                for block in 0..<(coefficients.count / 64) {
                    if block & 63 == 0 { try NativeOperation.check() }
                    reconstructBlock(base + block * 64, quantiser: qt,
                        matrix: mBase, transposed: tBase,
                        centre: centre, maximum: maximum, zero: zero)
                }
            }
        }
    }

    @inline(__always)
    private static func reconstructBlockAndCompactUInt16(
        _ coefficients: UnsafeMutablePointer<Int32>,
        rawDestination: UnsafeMutableRawPointer,
        quantiser: UnsafePointer<Float>,
        matrix: UnsafePointer<Float>, transposed: UnsafePointer<Float>,
        centre: SIMD8<Float>, maximum: SIMD8<Float>, zero: SIMD8<Float>,
        magicBias: SIMD8<Float>
    ) {
        let r0 = dequantise(coefficients, quantiser, row: 0,  0,  1,  5,  6, 14, 15, 27, 28)
        let r1 = dequantise(coefficients, quantiser, row: 1,  2,  4,  7, 13, 16, 26, 29, 42)
        let r2 = dequantise(coefficients, quantiser, row: 2,  3,  8, 12, 17, 25, 30, 41, 43)
        let r3 = dequantise(coefficients, quantiser, row: 3,  9, 11, 18, 24, 31, 40, 44, 53)
        let r4 = dequantise(coefficients, quantiser, row: 4, 10, 19, 23, 32, 39, 45, 52, 54)
        let r5 = dequantise(coefficients, quantiser, row: 5, 20, 22, 33, 38, 46, 51, 55, 60)
        let r6 = dequantise(coefficients, quantiser, row: 6, 21, 34, 37, 47, 50, 56, 59, 61)
        let r7 = dequantise(coefficients, quantiser, row: 7, 35, 36, 48, 49, 57, 58, 62, 63)
        coefficients.withMemoryRebound(to: Float.self, capacity: 64) { output in
            for row in 0..<8 {
                let first = dot(load(transposed, row: row), r0, r1, r2, r3, r4, r5, r6, r7)
                store(first, into: output, row: row)
            }
            let c0 = load(matrix, row: 0), c1 = load(matrix, row: 1)
            let c2 = load(matrix, row: 2), c3 = load(matrix, row: 3)
            let c4 = load(matrix, row: 4), c5 = load(matrix, row: 5)
            let c6 = load(matrix, row: 6), c7 = load(matrix, row: 7)
            for row in 0..<8 {
                let first = load(UnsafePointer(output), row: row)
                var value = dot(first, c0, c1, c2, c3, c4, c5, c6, c7) + centre
                value = value.replacing(with: zero, where: value .< zero)
                value = value.replacing(with: maximum, where: value .> maximum)
                let rounded = value.rounded(.toNearestOrAwayFromZero)
                let biasedBits = unsafeBitCast(rounded + magicBias, to: SIMD8<UInt32>.self)
                let words = SIMD8<UInt16>(truncatingIfNeeded: biasedBits)
                rawDestination.storeBytes(of: words, toByteOffset: row * 16, as: SIMD8<UInt16>.self)
            }
        }
    }

    @inline(__always)
    private static func reconstructBlockAndCompactUInt8(
        _ coefficients: UnsafeMutablePointer<Int32>,
        rawDestination: UnsafeMutableRawPointer,
        quantiser: UnsafePointer<Float>,
        matrix: UnsafePointer<Float>, transposed: UnsafePointer<Float>,
        centre: SIMD8<Float>, maximum: SIMD8<Float>, zero: SIMD8<Float>,
        magicBias: SIMD8<Float>
    ) {
        let r0 = dequantise(coefficients, quantiser, row: 0,  0,  1,  5,  6, 14, 15, 27, 28)
        let r1 = dequantise(coefficients, quantiser, row: 1,  2,  4,  7, 13, 16, 26, 29, 42)
        let r2 = dequantise(coefficients, quantiser, row: 2,  3,  8, 12, 17, 25, 30, 41, 43)
        let r3 = dequantise(coefficients, quantiser, row: 3,  9, 11, 18, 24, 31, 40, 44, 53)
        let r4 = dequantise(coefficients, quantiser, row: 4, 10, 19, 23, 32, 39, 45, 52, 54)
        let r5 = dequantise(coefficients, quantiser, row: 5, 20, 22, 33, 38, 46, 51, 55, 60)
        let r6 = dequantise(coefficients, quantiser, row: 6, 21, 34, 37, 47, 50, 56, 59, 61)
        let r7 = dequantise(coefficients, quantiser, row: 7, 35, 36, 48, 49, 57, 58, 62, 63)
        coefficients.withMemoryRebound(to: Float.self, capacity: 64) { output in
            for row in 0..<8 {
                let first = dot(load(transposed, row: row), r0, r1, r2, r3, r4, r5, r6, r7)
                store(first, into: output, row: row)
            }
            let c0 = load(matrix, row: 0), c1 = load(matrix, row: 1)
            let c2 = load(matrix, row: 2), c3 = load(matrix, row: 3)
            let c4 = load(matrix, row: 4), c5 = load(matrix, row: 5)
            let c6 = load(matrix, row: 6), c7 = load(matrix, row: 7)
            for row in 0..<8 {
                let first = load(UnsafePointer(output), row: row)
                var value = dot(first, c0, c1, c2, c3, c4, c5, c6, c7) + centre
                value = value.replacing(with: zero, where: value .< zero)
                value = value.replacing(with: maximum, where: value .> maximum)
                let rounded = value.rounded(.toNearestOrAwayFromZero)
                let biasedBits = unsafeBitCast(rounded + magicBias, to: SIMD8<UInt32>.self)
                let outBytes = SIMD8<UInt8>(truncatingIfNeeded: biasedBits)
                rawDestination.storeBytes(of: outBytes, toByteOffset: row * 8, as: SIMD8<UInt8>.self)
            }
        }
    }

    static func reconstructAndCompact(
        _ coefficients: UnsafeMutableBufferPointer<Int32>,
        quantiser: UnsafeBufferPointer<Float>,
        precision: Int, bytesPerSample: Int, floatOutput: Bool
    ) throws -> Bool {
        guard available, NativeDSP.usesAccelerate,
              UInt16(littleEndian: 1) == 1, !floatOutput,
              precision == 8 || precision == 12,
              (bytesPerSample == 1 && precision <= 8) || bytesPerSample == 2,
              !coefficients.isEmpty, coefficients.count % 64 == 0,
              coefficients.count <= SequentialGreyscalePlan.maximumWindowBlocks * 64,
              quantiser.count >= 64,
              let base = coefficients.baseAddress, let qt = quantiser.baseAddress else {
            return false
        }
        let absMask = SIMD8<UInt32>(repeating: 0x7FFF_FFFF)
        for qRow in 0..<8 {
            let qVec = load(qt, row: qRow)
            if (unsafeBitCast(qVec, to: SIMD8<UInt32>.self) & absMask).max() > 0x5F80_0000 {
                return false
            }
        }
        let centre = SIMD8<Float>(repeating: Float(1 << (precision - 1)))
        let maximum = SIMD8<Float>(repeating: Float((1 << precision) - 1))
        let zero = SIMD8<Float>(repeating: 0)
        let magicBias = SIMD8<Float>(repeating: 8_388_608.0)
        let rawSlot = UnsafeMutableRawPointer(base)
        let blockCount = coefficients.count / 64
        try AccelerateDSP.dctMatrix.withUnsafeBufferPointer { matrix in
            try AccelerateDSP.dctMatrixTransposed.withUnsafeBufferPointer { transposed in
                let mBase = matrix.baseAddress!
                let tBase = transposed.baseAddress!
                if bytesPerSample == 2 {
                    for block in 0..<blockCount {
                        if block & 63 == 0 { try NativeOperation.check() }
                        reconstructBlockAndCompactUInt16(
                            base + block * 64,
                            rawDestination: rawSlot + block * 128,
                            quantiser: qt, matrix: mBase, transposed: tBase,
                            centre: centre, maximum: maximum, zero: zero, magicBias: magicBias)
                    }
                } else {
                    for block in 0..<blockCount {
                        if block & 63 == 0 { try NativeOperation.check() }
                        reconstructBlockAndCompactUInt8(
                            base + block * 64,
                            rawDestination: rawSlot + block * 64,
                            quantiser: qt, matrix: mBase, transposed: tBase,
                            centre: centre, maximum: maximum, zero: zero, magicBias: magicBias)
                    }
                }
            }
        }
        return true
    }
}
