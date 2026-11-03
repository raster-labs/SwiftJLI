// SPDX-License-Identifier: Apache-2.0
// Standalone experiment only. No production source is changed.
// Exact dot/dequantisation graph follows ba2771e BlockLocalIDCT.swift.
import Foundation
import Darwin
@testable import SwiftJLI

enum MirrorFailure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let text): return text } }
}

struct MirrorCounts: Codable {
    var blocks = 0
    var rows = 0
    var certifiedPixels = 0
    var ambiguousPixels = 0
    var domainFallbackPixels = 0
    var auditedCertificates = 0
    var maximumRadius = 0.0
    var maximumObservedDifference = 0.0
    mutating func add(_ other: Self) {
        blocks += other.blocks; rows += other.rows
        certifiedPixels += other.certifiedPixels; ambiguousPixels += other.ambiguousPixels
        domainFallbackPixels += other.domainFallbackPixels
        auditedCertificates += other.auditedCertificates
        maximumRadius = max(maximumRadius, other.maximumRadius)
        maximumObservedDifference = max(maximumObservedDifference, other.maximumObservedDifference)
    }
}

/// Ordinary owning arrays only; no in-place rebinding in this prototype.
/// The first pass is exact. Only the second pass can be certified approximate.
struct CertifiedMirror {
    let matrix: [SIMD8<Float>]
    let transposed: [SIMD8<Float>]
    let mirror: [SIMD4<Float>]
    let weights: [Double]
    let inverseZigzag: [Int]
    let basisBits: [UInt32]
    let mirrorBits: [UInt32]
    let maximumMirrorResidual: Double
    let basisDomainValid: Bool
    let positiveSumInflation: Double

    /// Every bound operation below is nonnegative. nextUp encloses an RNE
    /// product/sum, including a positive product rounded down to zero.
    private static func upMultiply(_ a: Double, _ b: Double) -> Double {
        if a == 0 || b == 0 { return 0 }
        return (a * b).nextUp
    }
    private static func upAdd(_ a: Double, _ b: Double) -> Double {
        if a == 0 { return b }; if b == 0 { return a }
        return (a + b).nextUp
    }
    private static func gamma(_ count: Int, unit: Double) -> Double {
        // count*unit and1-count*unit are exact binary rationals for count<=8.
        let product = Double(count) * unit
        return (product / (1 - product)).nextUp
    }

    init() throws {
        guard fegetround() == FE_TONEAREST else { throw MirrorFailure.invalid("RNE required") }
        let m = AccelerateDSP.dctMatrix
        let mt = AccelerateDSP.dctMatrixTransposed
        guard m.count == 64, mt.count == 64 else { throw MirrorFailure.invalid("Basis extent") }
        func row8(_ values: [Float], _ row: Int) -> SIMD8<Float> {
            let i = row * 8
            return SIMD8(values[i], values[i+1], values[i+2], values[i+3],
                         values[i+4], values[i+5], values[i+6], values[i+7])
        }
        matrix = (0..<8).map { row8(m, $0) }
        transposed = (0..<8).map { row8(mt, $0) }
        inverseZigzag = Quantization.inverseZigzagOrder
        basisBits = m.map(\.bitPattern)
        var a = [Float](repeating: 0, count: 64)
        for frequency in 0..<8 {
            let sign: Double = frequency & 1 == 0 ? 1 : -1
            for position in 0..<4 {
                // These two Float values have closely bounded exponents;
                // Double sum and division by two are exact before RN32.
                let average = (Double(m[frequency*8+position])
                    + sign * Double(m[frequency*8+7-position])) / 2
                let value = Float(average)
                a[frequency*8+position] = value
                a[frequency*8+7-position] = frequency & 1 == 0 ? value : -value
            }
        }
        mirror = (0..<8).map { row in
            let i = row * 8
            return SIMD4(a[i], a[i+1], a[i+2], a[i+3])
        }
        mirrorBits = a.map(\.bitPattern)
        maximumMirrorResidual = zip(m, a).map { abs(Double($0.0) - Double($0.1)) }.max() ?? .infinity
        let grid = Double(1 << 27)
        // These checks support the normal-arithmetic proof: basis products
        // and accepted row inputs have exact grids2^-27, hence all nonzero
        // second-pass exact intermediate values are at least2^-54.
        basisDomainValid = (m + a).allSatisfy {
            let value = Double($0), scaled = value * grid
            return value.isFinite && abs(value) >= 0.0625 && abs(value) <= 0.5
                && scaled.rounded(.towardZero) == scaled
        }
        let unit32 = Double(1) / Double(1 << 24)
        var k = [Double](repeating: 0, count: 8)
        for frequency in 0..<8 {
            let referenceGamma = Self.gamma(8-frequency, unit: unit32)
            let candidateGamma = Self.gamma(5-frequency/2, unit: unit32)
            for position in 0..<8 {
                let original = Double(m[frequency*8+position])
                let approximate = Double(a[frequency*8+position])
                // Difference is exact in Double for the checked basis range.
                let residual = abs(original - approximate)
                let rounded = Self.upAdd(Self.upMultiply(abs(original), referenceGamma),
                                         Self.upMultiply(abs(approximate), candidateGamma))
                k[frequency] = max(k[frequency], Self.upAdd(rounded, residual))
            }
        }
        weights = k
        // Eight explicit positive Double FMAs have |s-S|<=gamma8*S.
        // Lower the denominator before division and raise its reciprocal.
        let unit64 = Double(1) / 9_007_199_254_740_992.0
        let gamma64 = Self.gamma(8, unit: unit64)
        let denominator = (1 - gamma64).nextDown
        positiveSumInflation = (1 / denominator).nextUp
    }

    @inline(__always)
    static func dot(_ a: SIMD8<Float>, _ b0: SIMD8<Float>, _ b1: SIMD8<Float>,
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
    func exactSecond(_ row: SIMD8<Float>) -> SIMD8<Float> {
        Self.dot(row, matrix[0], matrix[1], matrix[2], matrix[3],
                 matrix[4], matrix[5], matrix[6], matrix[7])
    }

    @inline(__always)
    func exactPixel(_ row: SIMD8<Float>, position: Int) -> Float {
        var result: Float = 0
        // Deliberately explicit ascending reference FMAs, without a reduction.
        result = result.addingProduct(row[0], matrix[0][position])
        result = result.addingProduct(row[1], matrix[1][position])
        result = result.addingProduct(row[2], matrix[2][position])
        result = result.addingProduct(row[3], matrix[3][position])
        result = result.addingProduct(row[4], matrix[4][position])
        result = result.addingProduct(row[5], matrix[5][position])
        result = result.addingProduct(row[6], matrix[6][position])
        result = result.addingProduct(row[7], matrix[7][position])
        return result
    }

    @inline(__always)
    func approximateSecond(_ row: SIMD8<Float>) -> SIMD8<Float> {
        var even = SIMD4<Float>(repeating: 0), odd = SIMD4<Float>(repeating: 0)
        even = even.addingProduct(SIMD4(repeating: row[0]), mirror[0])
        even = even.addingProduct(SIMD4(repeating: row[2]), mirror[2])
        even = even.addingProduct(SIMD4(repeating: row[4]), mirror[4])
        even = even.addingProduct(SIMD4(repeating: row[6]), mirror[6])
        odd = odd.addingProduct(SIMD4(repeating: row[1]), mirror[1])
        odd = odd.addingProduct(SIMD4(repeating: row[3]), mirror[3])
        odd = odd.addingProduct(SIMD4(repeating: row[5]), mirror[5])
        odd = odd.addingProduct(SIMD4(repeating: row[7]), mirror[7])
        let left = even + odd, right = even - odd
        return SIMD8(left[0], left[1], left[2], left[3], right[3], right[2], right[1], right[0])
    }

    func radius(_ row: SIMD8<Float>) -> Double? {
        guard basisDomainValid else { return nil }
        let grid = Double(1 << 27)
        for lane in 0..<8 {
            let value = Double(row[lane]), scaled = value * grid
            guard value.isFinite, abs(value) <= 4_294_967_296,
                  scaled.rounded(.towardZero) == scaled else { return nil }
        }
        // Bound products are normal Double numbers or exact zero in the
        // accepted row domain. The explicit FMAs preserve the stated depth.
        var sum = 0.0
        sum = sum.addingProduct(abs(Double(row[0])), weights[0])
        sum = sum.addingProduct(abs(Double(row[1])), weights[1])
        sum = sum.addingProduct(abs(Double(row[2])), weights[2])
        sum = sum.addingProduct(abs(Double(row[3])), weights[3])
        sum = sum.addingProduct(abs(Double(row[4])), weights[4])
        sum = sum.addingProduct(abs(Double(row[5])), weights[5])
        sum = sum.addingProduct(abs(Double(row[6])), weights[6])
        sum = sum.addingProduct(abs(Double(row[7])), weights[7])
        let result = sum == 0 ? 0 : (sum * positiveSumInflation).nextUp
        return result.isFinite && result >= 0 ? result : nil
    }

    static func centredClipped(_ sample: Float, precision: Int) -> Float {
        var value = sample + Float(1 << (precision-1))
        if value < 0 { value = 0 }
        let maximum = Float((1 << precision)-1)
        if value > maximum { value = maximum }
        return value
    }

    static func integerFromCentred(_ value: Float) throws -> UInt16 {
        guard value.isFinite, value >= 0, value <= 65535 else {
            throw MirrorFailure.invalid("Non-finite or out-of-range reconstructed sample")
        }
        return UInt16(value.rounded(.toNearestOrAwayFromZero))
    }

    static func certificate(_ sample: Float, radius: Double, precision: Int) -> UInt16? {
        guard sample.isFinite, radius.isFinite, radius >= 0,
              precision == 8 || precision == 12 else { return nil }
        // First enclose the uncentred reference Float. RNE conversion is
        // monotone and fixes every possible reference Float in[L,U]. Applying
        // the original Float addition/clip/round to converted endpoints then
        // encloses that same operation sequence without a Double level add.
        let lower = (Double(sample) - radius).nextDown
        let upper = (Double(sample) + radius).nextUp
        guard lower.isFinite, upper.isFinite else { return nil }
        let lo = centredClipped(Float(lower), precision: precision)
        let hi = centredClipped(Float(upper), precision: precision)
        guard lo.isFinite, hi.isFinite else { return nil }
        let a = UInt16(lo.rounded(.toNearestOrAwayFromZero))
        let b = UInt16(hi.rounded(.toNearestOrAwayFromZero))
        return a == b ? a : nil
    }

    func certifiedRow(_ row: SIMD8<Float>, precision: Int, audit: Bool,
                      output: inout [UInt16], offset: Int, counts: inout MirrorCounts) throws {
        counts.rows += 1
        guard let error = radius(row) else {
            counts.domainFallbackPixels += 8
            let exact = exactSecond(row)
            for lane in 0..<8 {
                output[offset+lane] = try Self.integerFromCentred(Self.centredClipped(exact[lane], precision: precision))
            }
            return
        }
        counts.maximumRadius = max(counts.maximumRadius, error)
        let approximate = approximateSecond(row)
        for lane in 0..<8 {
            let certified = Self.certificate(approximate[lane], radius: error, precision: precision)
            if audit {
                let reference = exactPixel(row, position: lane)
                let difference = abs(Double(reference) - Double(approximate[lane]))
                guard reference.isFinite, approximate[lane].isFinite, difference <= error else {
                    throw MirrorFailure.invalid("Transform interval failed at lane \(lane): difference=\(difference), radius=\(error)")
                }
                counts.maximumObservedDifference = max(counts.maximumObservedDifference, difference)
                if let certified {
                    let exactInteger = try Self.integerFromCentred(Self.centredClipped(reference, precision: precision))
                    guard certified == exactInteger else { throw MirrorFailure.invalid("Certificate integer mismatch") }
                    counts.auditedCertificates += 1
                }
            }
            if let certified {
                output[offset+lane] = certified
                counts.certifiedPixels += 1
            } else {
                counts.ambiguousPixels += 1
                output[offset+lane] = try Self.integerFromCentred(Self.centredClipped(exactPixel(row, position: lane), precision: precision))
            }
        }
    }

    func firstPass(_ coefficients: [Int32], offset: Int, quantiser: [Float],
                   into rows: inout [SIMD8<Float>]) {
        func dequantise(_ row: Int) -> SIMD8<Float> {
            let i = row * 8
            let values = SIMD8<Float>(Float(coefficients[offset+inverseZigzag[i]]),
                Float(coefficients[offset+inverseZigzag[i+1]]), Float(coefficients[offset+inverseZigzag[i+2]]),
                Float(coefficients[offset+inverseZigzag[i+3]]), Float(coefficients[offset+inverseZigzag[i+4]]),
                Float(coefficients[offset+inverseZigzag[i+5]]), Float(coefficients[offset+inverseZigzag[i+6]]),
                Float(coefficients[offset+inverseZigzag[i+7]]))
            let q = SIMD8(quantiser[i],quantiser[i+1],quantiser[i+2],quantiser[i+3],
                          quantiser[i+4],quantiser[i+5],quantiser[i+6],quantiser[i+7])
            return values * q
        }
        let r0=dequantise(0), r1=dequantise(1), r2=dequantise(2), r3=dequantise(3)
        let r4=dequantise(4), r5=dequantise(5), r6=dequantise(6), r7=dequantise(7)
        for row in 0..<8 { rows[row] = Self.dot(transposed[row],r0,r1,r2,r3,r4,r5,r6,r7) }
    }

    /// Both source-level timing arms use this same input/output allocation and
    /// exact first pass. This is not a full decode or an RSS comparison.
    func transform(_ coefficients: [Int32], quantiser: [Float], precision: Int,
                   certified: Bool, audit: Bool = false) throws -> ([UInt16], MirrorCounts) {
        guard fegetround() == FE_TONEAREST,
              !coefficients.isEmpty, coefficients.count % 64 == 0, quantiser.count == 64,
              precision == 8 || precision == 12 else { throw MirrorFailure.invalid("Transform extent") }
        var output = [UInt16](repeating: 0, count: coefficients.count)
        var first = [SIMD8<Float>](repeating: SIMD8(repeating: 0), count: 8)
        var counts = MirrorCounts()
        for block in 0..<(coefficients.count/64) {
            counts.blocks += 1
            firstPass(coefficients, offset: block*64, quantiser: quantiser, into: &first)
            for row in 0..<8 {
                if certified {
                    try certifiedRow(first[row], precision: precision, audit: audit,
                        output: &output, offset: block*64+row*8, counts: &counts)
                } else {
                    let exact = exactSecond(first[row])
                    for lane in 0..<8 {
                        output[block*64+row*8+lane] = try Self.integerFromCentred(Self.centredClipped(exact[lane], precision: precision))
                    }
                }
            }
        }
        return (output, counts)
    }
}
