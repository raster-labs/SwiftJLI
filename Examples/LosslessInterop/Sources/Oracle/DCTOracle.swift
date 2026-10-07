// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI

enum DCTOracle {
    static func run(_ command: String, root: URL) async throws {
        for bits in [8, 12] { for nc in [1, 3] { for script in 0...2 { for accelerated in [false, true] {
            let w = 31, h = 23, bps = bits == 8 ? 1 : 2, maxValue = (1 << bits) - 1
            let stem = "dct-\(bits)-\(nc)-\(script)-\(accelerated ? "auto" : "scalar")"
            let policy: ExecutionPolicy = accelerated ? .automatic : .scalarCPU
            let rowBytes = w * nc * bps + 8
            let plane = try PlaneDescriptor(width: w, height: h, components: Array(0..<nc), sampleStride: bps,
                pixelStride: nc * bps, rowBytes: rowBytes, byteCount: rowBytes * h)
            let descriptor = try ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
                components: nc == 1 ? [.grey] : [.red, .green, .blue], colour: nc == 1 ? .greyscale : .rgb, planes: [plane])
            func writePNM(_ image: Image, suffix: String) throws {
                var data = Data("\(nc == 1 ? "P5" : "P6")\n\(w) \(h)\n\(maxValue)\n".utf8)
                let p = image.descriptor.planes[0]
                try image.storage.withUnsafeBytes { bytes in
                    for y in 0..<h { for x in 0..<(w * nc) {
                        let offset = p.offset + y * p.rowBytes + x * bps
                        if bps == 2 { data.append(bytes[offset + 1]) }
                        data.append(bytes[offset])
                    } }
                }
                try data.write(to: root.appendingPathComponent("\(stem)-\(suffix).pnm"))
            }
            let decoder = try SwiftJLI.Decoder()
            if command == "generate-dct" {
                let image = try ImageDestination.allocate(descriptor: descriptor).write { bytes in
                    for y in 0..<h { for x in 0..<(w * nc) {
                        let sample = (x * 137 + y * 193 + x * y * 7) & maxValue
                        let offset = y * rowBytes + x * bps
                        bytes[offset] = UInt8(truncatingIfNeeded: sample)
                        if bps == 2 { bytes[offset + 1] = UInt8(sample >> 8) }
                    } }
                }
                let options = DCTOptions(quality: 85, chromaSubsampling: .yuv444,
                    progressiveMode: script == 0 ? .sequential : script == 1 ? .spectralSelection : .successiveApproximation,
                    adaptiveQuantisation: false, perceptualQuantisationTables: false)
                let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(restartInterval: 3, dct: options)))
                let encoded = try await encoder.encode(image, options: .init(executionPolicy: policy))
                try encoded.data.write(to: root.appendingPathComponent("\(stem)-swift.jpg"))
                try writePNM(image, suffix: "source")
                let decoded = try await decoder.decode(encoded.data, options: .init(executionPolicy: policy))
                try writePNM(decoded.image, suffix: "swift-self")
            } else {
                let data = try Data(contentsOf: root.appendingPathComponent("\(stem)-oracle.jpg"))
                let destination = try ImageDestination.allocate(descriptor: descriptor)
                let decoded = try await decoder.decode(data, into: destination, options: .init(executionPolicy: policy))
                guard decoded.report.pixelAllocationCount == 0, decoded.report.copyEvents.isEmpty else {
                    throw CodecError(.internalFailure, "Direct DCT decode copied pixels")
                }
                try writePNM(decoded.image, suffix: "swift-oracle")
            }
        } } } }
        print("24 \(command) cases passed")
    }
}
