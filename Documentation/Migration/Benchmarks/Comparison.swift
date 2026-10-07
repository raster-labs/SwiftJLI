import Foundation
import JLISwift
import SwiftJLI

func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
}
func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] * 1000 }
@main struct Benchmark {
    static func main() async throws {
        for (bits, nc) in [(8,3), (12,1)] {
            let w = 512, h = 512, bps = bits == 8 ? 1 : 2, row = w * nc * bps
            var bytes = [UInt8](repeating: 0, count: row * h)
            for y in 0..<h { for x in 0..<(w * nc) {
                let v = (x * 17 + y * 31 + x * y % 257) & ((1 << bits) - 1), offset = y * row + x * bps
                bytes[offset] = UInt8(truncatingIfNeeded: v)
                if bps == 2 { bytes[offset + 1] = UInt8(v >> 8) }
            } }
            let legacy = try JLIImage(width: w, height: h, pixelFormat: bits == 8 ? .uint8 : .uint16,
                colorModel: nc == 1 ? .grayscale : .rgb, data: bytes)
            let plane = try SwiftJLI.PlaneDescriptor(width: w, height: h, components: Array(0..<nc),
                sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: bytes.count)
            let descriptor = try SwiftJLI.ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
                components: nc == 1 ? [.grey] : [.red, .green, .blue], colour: nc == 1 ? .greyscale : .rgb, planes: [plane])
            let image = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor).write { $0.copyBytes(from: bytes) }
            let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy))
            let decoder = try SwiftJLI.Decoder()
            let oldJPEG = try JLIEncoder().encode(legacy)
            let newJPEG = try await encoder.encode(image)
            guard oldJPEG == Array(newJPEG.data) else { throw SwiftJLI.CodecError(.internalFailure, "Benchmark codestream differs") }
            var oldEncode: [Double] = [], newEncode: [Double] = [], oldDecode: [Double] = [], newDecode: [Double] = []
            var checksum = 0
            for i in 0..<11 {
                // Alternate pair order to reduce consistent thermal/order bias.
                for successor in i % 2 == 0 ? [false,true] : [true,false] {
                    var start = ContinuousClock.now
                    if successor {
                        let e = try await encoder.encode(image); let t = elapsed(start)
                        checksum ^= e.data.count; if i >= 3 { newEncode.append(t) }
                        start = .now
                        let d = try await decoder.decode(newJPEG.data); let dt = elapsed(start)
                        checksum ^= d.image.storage.byteCount; if i >= 3 { newDecode.append(dt) }
                    } else {
                        let e = try JLIEncoder().encode(legacy); let t = elapsed(start)
                        checksum ^= e.count; if i >= 3 { oldEncode.append(t) }
                        start = .now
                        let d = try JLIDecoder().decode(from: oldJPEG); let dt = elapsed(start)
                        checksum ^= d.data.count; if i >= 3 { oldDecode.append(dt) }
                    }
                }
            }
            let result: [String: Any] = ["bits": bits, "components": nc, "width": w, "height": h,
                "predecessorEncodeMS": median(oldEncode), "successorEncodeMS": median(newEncode),
                "predecessorDecodeMS": median(oldDecode), "successorDecodeMS": median(newDecode),
                "predecessorEncodeSamples": oldEncode, "successorEncodeSamples": newEncode,
                "predecessorDecodeSamples": oldDecode, "successorDecodeSamples": newDecode,
                "jpegBytes": oldJPEG.count, "checksum": checksum]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
        }
    }
}
