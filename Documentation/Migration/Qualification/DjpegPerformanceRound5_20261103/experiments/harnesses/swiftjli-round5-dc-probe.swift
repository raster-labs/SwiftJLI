import Foundation
@testable import SwiftJLI

@main struct DCProbe {
    static func main() throws {
        var checked = 0
        for backend: Backend in [.scalarCPU, .accelerated] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
                let basis = AccelerateDSP.dctMatrix[0]
                for quantiser: Float in [1, 3, 255, 65535] {
                    let dcValues: [Int32] = quantiser == 1
                        ? (-16384...16384).map(Int32.init)
                        : [-16384, -8192, -4097, -1024, -1, 0, 1, 1024, 4097, 8192, 16384]
                    for first in stride(from: 0, to: dcValues.count, by: 1024) {
                        let count = min(1024, dcValues.count - first)
                        var coefficients = [Int32](repeating: 0, count: count * 64)
                        for block in 0..<count { coefficients[block * 64] = dcValues[first + block] }
                        let quantisers = [Float](repeating: quantiser, count: 64)
                        var output = [Float](repeating: 0, count: count * 64)
                        var scratch = output
                        coefficients.withUnsafeBufferPointer { c in
                            quantisers.withUnsafeBufferPointer { q in
                                output.withUnsafeMutableBufferPointer { o in
                                    scratch.withUnsafeMutableBufferPointer { s in
                                        AccelerateDSP.inverseDCTBatchDequantized(zigzag: c.baseAddress!,
                                            quantTable: q.baseAddress!, output: o.baseAddress!,
                                            scratch: s.baseAddress!, blockCount: count)
                                    }
                                }
                            }
                        }
                        for block in 0..<count {
                            let value = ((Float(dcValues[first + block]) * quantiser) * basis) * basis
                            for sample in 0..<64 {
                                guard output[block * 64 + sample].bitPattern == value.bitPattern else {
                                    throw NSError(domain: "DCProbe", code: 1, userInfo: [
                                        NSLocalizedDescriptionKey: "backend=\(backend) q=\(quantiser) dc=\(dcValues[first + block]) sample=\(sample) actual=\(output[block * 64 + sample].bitPattern) expected=\(value.bitPattern)"])
                                }
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        print("Exact Float bit comparisons: \(checked)")
    }
}
