// SPDX-License-Identifier: Apache-2.0
import Foundation
@testable import SwiftJLI

struct RGBOutputBatchTests {
    func batchEdgesPaddedRowsAndFractionalSamplesMatchNativeOutput() throws {
        var backends: [Backend] = [.scalarCPU]
        #if canImport(Accelerate)
        backends.append(.accelerated)
        #endif
        for backend in backends { for workers in [1, 8] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: workers)) {
                for width in [1, 19, 257] { for height in [1, 7, 8, 9, 17, 257] {
                    let count = width * height
                    let y = (0..<count).map { Float(($0 * 73) % 256) + 0.5 }
                    let cb = (0..<count).map { Float(($0 * 17) % 256) + 0.25 }
                    let cr = (0..<count).map { Float(($0 * 31) % 256) + 0.75 }
                    let expected = AccelerateDSP.imageYCbCrToRGB(y: y, cb: cb, cr: cr, pixelCount: count)
                    for sourcePadding in [0, 3] { for padding in [0, 11] {
                        let sourceWidth = width + sourcePadding
                        var sourceY = [Float](repeating: -999, count: sourceWidth * height)
                        for row in 0..<height {
                            sourceY.replaceSubrange((row * sourceWidth)..<(row * sourceWidth + width),
                                with: y[(row * width)..<((row + 1) * width)])
                        }
                        let rowBytes = width * 3 + padding, prefix = 13, suffix = 17
                        var output = [UInt8](repeating: 0xA5, count: prefix + rowBytes * height + suffix)
                        try output.withUnsafeMutableBytes { raw in
                            try SharedDCTStorage.write([(sourceY, sourceWidth, height), (cb, width, height), (cr, width, height)],
                                width: width, height: height, precision: 8, floatOutput: false,
                                into: .init(bytes: .init(rebasing: raw[prefix..<(prefix + rowBytes * height)]),
                                    rowBytes: rowBytes, bytesPerSample: 1))
                        }
                        try expect(output.prefix(prefix).allSatisfy { $0 == 0xA5 })
                        try expect(output.suffix(suffix).allSatisfy { $0 == 0xA5 })
                        for row in 0..<height {
                            let start = prefix + row * rowBytes, end = start + width * 3
                            try expect(output[start..<end].elementsEqual(expected[(row * width * 3)..<((row + 1) * width * 3)]))
                            try expect(output[end..<(start + rowBytes)].allSatisfy { $0 == 0xA5 })
                        }
                    } }
                } }
            }
        } }
    }
}

func expect(_ condition: Bool) throws {
    if !condition { throw CodecError(.internalFailure, "RGB output/padding comparison failed") }
}
@main struct Probe {
    static func main() throws {
        try RGBOutputBatchTests().batchEdgesPaddedRowsAndFractionalSamplesMatchNativeOutput()
        print("RGB output matches native: scalar/accelerated, workers 1/8, batch edges, padded source and guarded destination")
    }
}
