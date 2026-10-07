// SPDX-License-Identifier: Apache-2.0
// Scalar equivalents of the small vector/matrix operations used by the native
// JPEG kernels. Internal buffers and dimensions are validated by their callers.
// No Apple framework is imported on Linux.
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

enum NativeDSP {
    static var usesAccelerate: Bool {
        #if canImport(Accelerate)
        return NativeOperation.current?.backend != .scalarCPU
        #else
        return false
        #endif
    }
}

typealias JLI_DSPCount = Int
typealias JLI_DSPStride = Int

func jliDSP_mmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ m: Int, _ n: Int, _ p: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_mmul(a, sa, b, sb, out, so, vDSP_Length(m), vDSP_Length(n), vDSP_Length(p))
        return
    }
    #endif
    for i in 0..<m { for j in 0..<n {
        var sum: Float = 0
        for k in 0..<p { sum += a[(i * p + k) * sa] * b[(k * n + j) * sb] }
        out[(i * n + j) * so] = sum
    } }
}
func jliDSP_vadd(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vadd(a, sa, b, sb, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = a[i * sa] + b[i * sb] }
}
func jliDSP_vmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vmul(a, sa, b, sb, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = a[i * sa] * b[i * sb] }
}
func jliDSP_vsadd(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vsadd(a, sa, b, out, so, vDSP_Length(n))
        return
    }
    #endif
    let scalar = b.pointee
    for i in 0..<n { out[i * so] = a[i * sa] + scalar }
}
func jliDSP_vsmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vsmul(a, sa, b, out, so, vDSP_Length(n))
        return
    }
    #endif
    let scalar = b.pointee
    for i in 0..<n { out[i * so] = a[i * sa] * scalar }
}
func jliDSP_vsma(_ a: UnsafePointer<Float>, _ sa: Int, _ scalar: UnsafePointer<Float>,
               _ b: UnsafePointer<Float>, _ sb: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vsma(a, sa, scalar, b, sb, out, so, vDSP_Length(n))
        return
    }
    #endif
    let scale = scalar.pointee
    for i in 0..<n { out[i * so] = a[i * sa] * scale + b[i * sb] }
}
func jliDSP_vclip(_ a: UnsafePointer<Float>, _ sa: Int, _ lo: UnsafePointer<Float>, _ hi: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vclip(a, sa, lo, hi, out, so, vDSP_Length(n))
        return
    }
    #endif
    let lower = lo.pointee, upper = hi.pointee
    for i in 0..<n { out[i * so] = min(upper, max(lower, a[i * sa])) }
}
func jliDSP_vfltu8(_ a: UnsafePointer<UInt8>, _ sa: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vfltu8(a, sa, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = Float(a[i * sa]) }
}
func jliDSP_vflt32(_ a: UnsafePointer<Int32>, _ sa: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vflt32(a, sa, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = Float(a[i * sa]) }
}
func jliDSP_vfix32(_ a: UnsafePointer<Float>, _ sa: Int, _ out: UnsafeMutablePointer<Int32>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vfix32(a, sa, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = Int32(a[i * sa]) }
}
func jliDSP_vfixru8(_ a: UnsafePointer<Float>, _ sa: Int, _ out: UnsafeMutablePointer<UInt8>, _ so: Int, _ n: Int) {
    #if canImport(Accelerate)
    if NativeDSP.usesAccelerate {
        Accelerate.vDSP_vfixru8(a, sa, out, so, vDSP_Length(n))
        return
    }
    #endif
    for i in 0..<n { out[i * so] = UInt8(min(255, max(0, a[i * sa].rounded(.toNearestOrEven)))) }
}
