// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct BoundedRGBOutputTests {
    @Test(arguments: [0, 5], [Backend.scalarCPU, .accelerated])
    func joinedInternalTilesMatchSerialOutputAndPreservePadding(sourcePadding: Int, backend: Backend) throws {
        let width = 257, height = 259, sourceWidth = width + sourcePadding
        let stride = width * 3 + 11
        let y = (0..<(sourceWidth * height)).map { Float(($0 * 73) % 401) - 51.5 }
        let cb = (0..<(width * height)).map { Float(($0 * 19) % 301) - 12.25 }
        let cr = (0..<(width * height)).map { Float(($0 * 31) % 289) + 0.5 }
        let planes = [(data: y, width: sourceWidth, height: height),
                      (data: cb, width: width, height: height),
                      (data: cr, width: width, height: height)]
        func render(workers: Int) throws -> [UInt8] {
            var result = [UInt8](repeating: 0xA5, count: 1 + stride * height + 3)
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: workers)) {
                try result.withUnsafeMutableBytes { raw in
                    let destination = BorrowedSampleDestination(bytes: .init(rebasing: raw[1..<(1 + stride * height)]),
                        rowBytes: stride, bytesPerSample: 1)
                    try SharedDCTStorage.write(planes, width: width, height: height,
                        precision: 8, into: destination)
                }
            }
            #expect(result[0] == 0xA5 && result.suffix(3).allSatisfy { $0 == 0xA5 })
            for row in 0..<height {
                let padding = (1 + row * stride + width * 3)..<(1 + (row + 1) * stride)
                #expect(result[padding].allSatisfy { $0 == 0xA5 })
            }
            return result
        }
        let serial = try render(workers: 1)
        for workers in [3, 8] { #expect(try render(workers: workers) == serial) }
    }
}
