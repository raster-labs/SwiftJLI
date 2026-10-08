// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit
import Darwin
import JLISwift
import SwiftJLI
func rss() -> Int { var r = rusage(); precondition(getrusage(RUSAGE_SELF, &r) == 0); return r.ru_maxrss }
func hash(_ raw: UnsafeRawBufferPointer) -> String {
    var h = SHA256(); h.update(bufferPointer: raw)
    return h.finalize().map { String(format: "%02x", $0) }.joined()
}
@main struct Memory {
    static func main() async throws {
        let a = CommandLine.arguments
        guard a.count == 6, let size = Int(a[3]), [512, 2048].contains(size) else { throw SwiftJLI.CodecError(.invalidArgument, "implementation operation size profile JPEG-path required") }
        let implementation = a[1], operation = a[2], profile = a[4], url = URL(fileURLWithPath: a[5])
        let bits = profile == "lossless16" ? 16 : profile == "dct12" ? 12 : 8
        let nc = bits == 8 ? 3 : 1, bps = bits > 8 ? 2 : 1, row = size * nc * bps
        let oldConfig = JLIEncoderConfiguration(chromaSubsampling: profile == "xyb8" ? .yuv444 : .yuv420,
            colorSpace: profile == "xyb8" ? .xyb : .yCbCr, progressive: profile == "progressiveRGB8",
            lossless: bits == 16, losslessPrecision: bits == 16 ? 16 : 0)
        let config = try SwiftJLI.EncoderConfiguration(mode: bits == 16 ? .lossless : .lossy,
            codecOptions: bits == 16 ? .init() : .init(dct: .init(chromaSubsampling: profile == "xyb8" ? .yuv444 : .yuv420,
                progressiveMode: profile == "progressiveRGB8" ? .spectralSelection : .sequential,
                colourSpace: profile == "xyb8" ? .xybFromSRGB : .yCbCr)))
        let limits = try SwiftJLI.ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
            maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        var digest = "", outputBytes = 0, before = 0
        if operation == "encode" || operation == "prepare" {
            var bytes = [UInt8](repeating: 0, count: row * size)
            for y in 0..<size { for x in 0..<(size * nc) {
                let v = (x * 17 + y * 31 + x * y % 257) & ((1 << bits) - 1), p = y * row + x * bps
                bytes[p] = UInt8(truncatingIfNeeded: v)
                if bps == 2 { bytes[p + 1] = UInt8(v >> 8) }
            } }
            if implementation == "predecessor" {
                let image = try JLIImage(width: size, height: size, pixelFormat: bits == 8 ? .uint8 : .uint16,
                    colorModel: nc == 1 ? .grayscale : .rgb, data: bytes)
                bytes.removeAll(keepingCapacity: false)
                before = rss()
                for _ in 0..<(operation == "prepare" ? 1 : 25) {
                    let encoded = try JLIEncoder().encode(image, configuration: oldConfig)
                    if operation == "prepare" { try Data(encoded).write(to: url); return }
                    outputBytes = encoded.count; digest = encoded.withUnsafeBytes(hash)
                }
            } else {
                let p = try SwiftJLI.PlaneDescriptor(width: size, height: size, components: Array(0..<nc),
                    sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: bytes.count)
                let d = try SwiftJLI.ImageDescriptor(width: size, height: size, storageBits: bps * 8, meaningfulBits: bits,
                    components: nc == 1 ? [.grey] : [.red, .green, .blue], colour: nc == 1 ? .greyscale : .rgb, planes: [p])
                let image = try SwiftJLI.ImageDestination.allocate(descriptor: d).write { $0.copyBytes(from: bytes) }
                bytes.removeAll(keepingCapacity: false)
                let encoder = try SwiftJLI.Encoder(configuration: config)
                before = rss()
                for _ in 0..<25 {
                    let encoded = try await encoder.encode(image, options: .init(resourceLimits: limits))
                    outputBytes = encoded.data.count; digest = encoded.data.withUnsafeBytes(hash)
                }
            }
        } else {
            if implementation == "predecessor" {
                let jpeg = Array(try Data(contentsOf: url)); before = rss()
                for _ in 0..<25 {
                    let decoded = try JLIDecoder().decode(from: jpeg)
                    outputBytes = decoded.data.count; digest = decoded.data.withUnsafeBytes(hash)
                }
            } else {
                let jpeg = try Data(contentsOf: url), decoder = try SwiftJLI.Decoder(); before = rss()
                for _ in 0..<25 {
                    let decoded = try await decoder.decode(jpeg, options: .init(resourceLimits: limits))
                    outputBytes = decoded.image.storage.byteCount; digest = try decoded.image.storage.withUnsafeBytes(hash)
                }
            }
        }
        let record: [String: Any] = ["implementation": implementation, "operation": operation, "size": size,
            "profile": profile, "iterations": 25, "processPeakRSSBeforeOperationBytes": before,
            "processPeakRSSBytes": rss(), "outputBytes": outputBytes, "outputSHA256": digest,
            "note": "Fresh process per implementation/operation/case; RSS includes runtime and allocator memory; not pure workspace or a latency measurement."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), as: UTF8.self))
    }
}
