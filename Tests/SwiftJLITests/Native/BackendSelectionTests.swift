// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Test func scalarRoundingMatchesAccelerateTieRule() {
    let input: [Float] = [0.5, 1.5, 2.5, 3.5, 127.5, 128.5, 254.5]
    let expected: [UInt8] = [0, 2, 2, 4, 128, 128, 254]
    for backend: Backend in [.scalarCPU, .accelerated] {
        let output = NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
            var output = [UInt8](repeating: 0, count: input.count)
            jliDSP_vfixru8(input, 1, &output, 1, input.count)
            return output
        }
        #expect(output == expected)
    }
}

@Test func scalarMatrixHonoursStridesAndDimensions() {
    NativeOperation.$current.withValue(.init(seconds: 120)) {
        let a: [Float] = [1,2,3,4,5,6], b: [Float] = [7,8,9,10,11,12]
        var output: [Float] = [-1,-1,-1,-1,-1,-1,-1,-1]
        jliDSP_mmul(a, 1, b, 1, &output, 2, 2, 2, 3)
        #expect(output == [58,-1,64,-1,139,-1,154,-1])
    }
}

@Test func DCTBackendSelectionPreservesNumericalAccuracy() {
    let input = (0..<64).map { Float(($0 * 61) % 255) - 128 }
    func transform(_ backend: Backend) -> ([Float], [Float]) {
        NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
            let coefficients = DCT.forward(input)
            return (coefficients, DCT.inverse(coefficients))
        }
    }
    let (scalar, reconstructed) = transform(.scalarCPU)
    let (accelerated, reconstructedAccelerated) = transform(.accelerated)
    for i in input.indices {
        // Float accumulation ordering differs between scalar and vector GEMM.
        // 0.001 is below one thousandth of an 8-bit source sample unit.
        #expect(abs(scalar[i] - accelerated[i]) < 0.001)
        #expect(abs(input[i] - reconstructed[i]) < 0.001)
        #expect(abs(input[i] - reconstructedAccelerated[i]) < 0.001)
    }
}
