// SPDX-License-Identifier: Apache-2.0
import Foundation
import JLISwift
import SwiftJLI
import Darwin

@main struct DistanceComparison {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Distance comparison failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        for distance in [26.0, 1000.0, Double.greatestFiniteMagnitude] {
            for profile in ["grey8", "grey12", "rgb8", "rgb12", "progressiveRGB8", "xyb8", "jpegliAQ"] {
                let bits = profile.hasSuffix("12") ? 12 : 8, nc = profile.hasPrefix("grey") ? 1 : 3
                let w = 17, h = 9, bps = bits == 8 ? 1 : 2, row = w * nc * bps
                var bytes = [UInt8](repeating: 0, count: row * h)
                for i in 0..<(w * h * nc) {
                    let v = (i * 79 + i * i) & ((1 << bits) - 1)
                    bytes[i * bps] = UInt8(truncatingIfNeeded: v)
                    if bps == 2 { bytes[i * bps + 1] = UInt8(v >> 8) }
                }
                let oldImage = try JLIImage(width: w, height: h, pixelFormat: bps == 1 ? .uint8 : .uint16,
                    colorModel: nc == 1 ? .grayscale : .rgb, data: bytes)
                let p = try SwiftJLI.PlaneDescriptor(width: w, height: h, components: Array(0..<nc),
                    sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: bytes.count)
                let d = try SwiftJLI.ImageDescriptor(width: w, height: h, storageBits: bps * 8,
                    meaningfulBits: bits, components: nc == 1 ? [.grey] : [.red, .green, .blue],
                    colour: nc == 1 ? .greyscale : .rgb, planes: [p])
                let image = try SwiftJLI.ImageDestination.allocate(descriptor: d).write { $0.copyBytes(from: bytes) }
                let xyb = profile == "xyb8", progressive = profile == "progressiveRGB8", aq = profile == "jpegliAQ"
                let oldOptions = JLIEncoderConfiguration(distance: distance,
                    chromaSubsampling: xyb ? .yuv444 : .yuv420, colorSpace: xyb ? .xyb : .yCbCr,
                    progressive: progressive, jpegliAdaptiveQuant: aq)
                let newOptions = SwiftJLI.DCTOptions(distance: distance,
                    chromaSubsampling: xyb ? .yuv444 : .yuv420,
                    progressiveMode: progressive ? .spectralSelection : .sequential,
                    jpegliAdaptiveQuantisation: aq, colourSpace: xyb ? .xybFromSRGB : .yCbCr)
                let original: [UInt8]?
                if distance == .greatestFiniteMagnitude { original = nil }
                else { original = try JLIEncoder().encode(oldImage, configuration: oldOptions) }
                let migrated = try await SwiftJLI.Encoder(configuration: .init(mode: .lossy,
                    codecOptions: .init(dct: newOptions))).encode(image)
                let newPixels = try await SwiftJLI.Decoder().decode(migrated.data)
                guard newPixels.image.descriptor.width == w, newPixels.image.descriptor.height == h,
                      newPixels.image.descriptor.meaningfulBits == bits, newPixels.image.storage.byteCount == bytes.count else {
                    throw SwiftJLI.CodecError(.internalFailure, "Distance output interpretation changed")
                }
                var result: [String: Any] = ["distance": distance, "profile": profile,
                    "compressedBytes": migrated.data.count, "successorDecoded": true, "predecessorCompared": original != nil]
                if let original {
                    guard original == Array(migrated.data) else {
                        throw SwiftJLI.CodecError(.internalFailure, "Distance \(distance)/\(profile) codestream differs")
                    }
                    let oldPixels = try JLIDecoder().decode(from: original).data
                    guard try newPixels.image.storage.withUnsafeBytes({ Array($0) }) == oldPixels else {
                        throw SwiftJLI.CodecError(.internalFailure, "Distance \(distance)/\(profile) samples differ")
                    }
                    result["codestreamsEqual"] = true; result["samplesEqual"] = true
                }
                print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
            }
        }
    }
}
