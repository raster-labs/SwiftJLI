// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI

enum RawRGBOracle {
    static func run(root: URL) async throws {
        for bits in [8, 12] { for progressive in [false, true] {
            let stem = "rgb-\(bits)-\(progressive ? "progressive" : "sequential")"
            let input = try Data(contentsOf: root.appendingPathComponent(stem + ".jpg"))
            let decoder = try SwiftJLI.Decoder()
            let info = try decoder.inspect(input)
            let d = info.descriptor
            guard d.colour == .rgb, d.meaningfulBits == bits, d.components.count == 3 else {
                throw CodecError(.internalFailure, "Raw RGB interpretation differs")
            }
            let bps = bits == 8 ? 1 : 2, row = d.width * 3 * bps + 16
            let plane = try PlaneDescriptor(width: d.width, height: d.height,
                components: [0, 1, 2], offset: 16, sampleStride: bps, pixelStride: 3 * bps,
                rowBytes: row, byteCount: 16 + row * d.height)
            let padded = try ImageDescriptor(width: d.width, height: d.height, storageBits: bps * 8,
                meaningfulBits: bits, components: [.red, .green, .blue], colour: .rgb, planes: [plane])
            for (backend, policy) in [("scalar", ExecutionPolicy.scalarCPU), ("auto", .automatic)] {
                for borrowed in [false, true] {
                    let destination = try ImageDestination.allocate(descriptor: padded)
                    let result = borrowed
                        ? try await decoder.decode(input, into: destination, options: .init(executionPolicy: policy))
                        : try await decoder.decode(input, options: .init(executionPolicy: policy))
                    if borrowed {
                        guard result.image.storage.allocationID == destination.storage.allocationID,
                              result.report.pixelAllocationCount == 0, result.report.copyEvents.isEmpty else {
                            throw CodecError(.internalFailure, "Raw RGB caller-storage copy")
                        }
                    }
                    let p = result.image.descriptor.planes[0]
                    var pnm = Data("P6\n\(d.width) \(d.height)\n\((1 << bits) - 1)\n".utf8)
                    try result.image.storage.withUnsafeBytes { bytes in
                        if borrowed {
                            guard bytes.prefix(16).allSatisfy({ $0 == 0 }) else {
                                throw CodecError(.internalFailure, "Raw RGB prefix overwritten")
                            }
                        }
                        for y in 0..<d.height {
                            for x in 0..<(d.width * 3) {
                                let index = p.offset + y * p.rowBytes + x * bps
                                if bps == 2 { pnm.append(bytes[index + 1]) }
                                pnm.append(bytes[index])
                            }
                            if borrowed {
                                let start = p.offset + y * row + d.width * 3 * bps
                                guard bytes[start..<(p.offset + (y + 1) * row)].allSatisfy({ $0 == 0 }) else {
                                    throw CodecError(.internalFailure, "Raw RGB row padding overwritten")
                                }
                            }
                        }
                    }
                    try pnm.write(to: root.appendingPathComponent("\(stem)-\(backend)-\(borrowed ? "borrowed" : "allocated").pnm"))
                }
            }
        } }
        print("16 independent raw RGB decode/storage cases passed")
    }
}
