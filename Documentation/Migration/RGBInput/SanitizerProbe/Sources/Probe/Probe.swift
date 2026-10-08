// SPDX-License-Identifier: Apache-2.0
import Foundation
@testable import SwiftJLI

struct RGBInputBatchTests {
    func paddedRowsBatchEdgesAndWorkersMatchNativePlanes() throws {
        var backends: [Backend] = [.scalarCPU]
        #if canImport(Accelerate)
        backends.append(.accelerated)
        #endif
        for backend in backends { for workers in [1, 8] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: workers)) {
                for width in [1, 19, 257] { for height in [1, 7, 8, 9, 17, 257] {
                    var packed = [UInt8](repeating: 0, count: width * height * 3)
                    for i in packed.indices { packed[i] = UInt8(truncatingIfNeeded: i * 73 + i / (width * 3) * 19) }
                    let expected = AccelerateDSP.imageRGBToYCbCr(data: packed, pixelCount: width * height, componentCount: 3)
                    for padding in [0, 11] {
                        let rowBytes = width * 3 + padding, prefix = 13, suffix = 17
                        var storage = [UInt8](repeating: 0xA5, count: prefix + rowBytes * height + suffix)
                        for row in 0..<height {
                            let start = prefix + row * rowBytes
                            storage.replaceSubrange(start..<(start + width * 3),
                                with: packed[(row * width * 3)..<((row + 1) * width * 3)])
                        }
                        let before = storage
                        let result = try storage.withUnsafeBytes { raw in
                            try SharedDCTStorage.read(.init(bytes: .init(rebasing: raw[prefix..<(prefix + rowBytes * height)]), rowBytes: rowBytes),
                                width: width, height: height, components: 3, precision: 8)
                        }
                        try expect(result.y == expected.y)
                        try expect(result.cb == expected.cb)
                        try expect(result.cr == expected.cr)
                        try expect(storage == before)
                    }
                } }
            }
        } }
    }
}

func expect(_ condition: Bool) throws {
    if !condition { throw CodecError(.internalFailure, "RGB input plane/source comparison failed") }
}
@main struct Probe {
    static func main() throws {
        try RGBInputBatchTests().paddedRowsBatchEdgesAndWorkersMatchNativePlanes()
        print("RGB input planes match native: scalar/accelerated, workers 1/8, batch edges, guarded/padded source unchanged")
    }
}
