// SPDX-License-Identifier: Apache-2.0
// Scalar equivalents of the small vector/matrix operations used by the native
// JPEG kernels. Internal buffers and dimensions are validated by their callers.
// No Apple framework is imported on Linux.
#if !canImport(Accelerate)
import Foundation

typealias vDSP_Length = Int
typealias vDSP_Stride = Int

func vDSP_mmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ m: Int, _ n: Int, _ p: Int) {
    for i in 0..<m { for j in 0..<n {
        var sum: Float = 0
        for k in 0..<p { sum += a[(i * p + k) * sa] * b[(k * n + j) * sb] }
        out[(i * n + j) * so] = sum
    } }
}
func vDSP_vadd(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = a[i * sa] + b[i * sb] }
}
func vDSP_vmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>, _ sb: Int,
               _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = a[i * sa] * b[i * sb] }
}
func vDSP_vsadd(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    let scalar = b.pointee
    for i in 0..<n { out[i * so] = a[i * sa] + scalar }
}
func vDSP_vsmul(_ a: UnsafePointer<Float>, _ sa: Int, _ b: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    let scalar = b.pointee
    for i in 0..<n { out[i * so] = a[i * sa] * scalar }
}
func vDSP_vsma(_ a: UnsafePointer<Float>, _ sa: Int, _ scalar: UnsafePointer<Float>,
               _ b: UnsafePointer<Float>, _ sb: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    let scale = scalar.pointee
    for i in 0..<n { out[i * so] = a[i * sa] * scale + b[i * sb] }
}
func vDSP_vclip(_ a: UnsafePointer<Float>, _ sa: Int, _ lo: UnsafePointer<Float>, _ hi: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    let lower = lo.pointee, upper = hi.pointee
    for i in 0..<n { out[i * so] = min(upper, max(lower, a[i * sa])) }
}
func vDSP_vfltu8(_ a: UnsafePointer<UInt8>, _ sa: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = Float(a[i * sa]) }
}
func vDSP_vflt32(_ a: UnsafePointer<Int32>, _ sa: Int, _ out: UnsafeMutablePointer<Float>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = Float(a[i * sa]) }
}
func vDSP_vfix32(_ a: UnsafePointer<Float>, _ sa: Int, _ out: UnsafeMutablePointer<Int32>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = Int32(a[i * sa]) }
}
func vDSP_vfixru8(_ a: UnsafePointer<Float>, _ sa: Int, _ out: UnsafeMutablePointer<UInt8>, _ so: Int, _ n: Int) {
    for i in 0..<n { out[i * so] = UInt8(min(255, max(0, a[i * sa].rounded()))) }
}
#endif
