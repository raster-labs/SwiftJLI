// SPDX-License-Identifier: Apache-2.0
import Foundation
import JLISwift
import SwiftJLI
import Darwin

@main struct ColourComparison {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Colour comparison failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        var count = 0
        for profile in ["rgba", "yCbCr", "rgbGrey", "rgbaGrey", "rgbaXYB"] {
            for bits in (profile == "rgba" ? [8, 12, 32] : [8, 32]) {
                for width in [1, 19] {
                    let height = 9, nc = profile.hasPrefix("rgba") ? 4 : 3
                    let bps = bits == 32 ? 4 : bits == 12 ? 2 : 1
                    let row = width * nc * bps, paddedRow = row + 4 * bps, offset = 8
                    var packed = [UInt8](repeating: 0, count: row * height)
                    for i in 0..<(width * height * nc) {
                        let value = (i * 29 + i * i) & (bits == 12 ? 4095 : 255)
                        let raw = bits == 32 ? (Float(value) / 255).bitPattern : UInt32(value)
                        for byte in 0..<bps { packed[i * bps + byte] = UInt8(truncatingIfNeeded: raw >> (8 * byte)) }
                    }
                    let oldImage = try JLIImage(width: width, height: height,
                        pixelFormat: bits == 32 ? .float32 : bits == 12 ? .uint16 : .uint8,
                        colorModel: nc == 4 ? .rgba : profile == "yCbCr" ? .yCbCr : .rgb, data: packed)
                    let p = try SwiftJLI.PlaneDescriptor(width: width, height: height, components: Array(0..<nc),
                        offset: offset, sampleStride: bps, pixelStride: nc * bps, rowBytes: paddedRow, byteCount: offset + paddedRow * height)
                    let d = try SwiftJLI.ImageDescriptor(width: width, height: height,
                        sampleType: bits == 32 ? .floatingPoint : .unsignedInteger,
                        storageBits: bps * 8, meaningfulBits: bits,
                        components: nc == 4 ? [.red, .green, .blue, .alpha] : profile == "yCbCr" ? [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")] : [.red, .green, .blue],
                        colour: profile == "yCbCr" ? .unknown : .rgb, alpha: nc == 4 ? .straight : .absent, planes: [p])
                    let image = try SwiftJLI.ImageDestination.allocate(descriptor: d).write { raw in
                        raw.initializeMemory(as: UInt8.self, repeating: 0xFF)
                        for y in 0..<height { for x in 0..<row { raw[offset + y * paddedRow + x] = packed[y * row + x] } }
                    }
                    let grey = profile.hasSuffix("Grey"), xyb = profile.hasSuffix("XYB")
                    for sampling in (grey || xyb ? [0] : [0, 1, 2]) {
                        for scan in (xyb ? [0] : [0, 1, 2]) {
                            let oldOptions = JLIEncoderConfiguration(chromaSubsampling: grey ? .yuv400 : sampling == 0 ? .yuv444 : sampling == 1 ? .yuv422 : .yuv420,
                                colorSpace: xyb ? .xyb : .yCbCr, progressive: scan != 0,
                                progressiveMode: scan == 2 ? .successiveApproximation : .spectralSelection)
                            let options = SwiftJLI.DCTOptions(chromaSubsampling: grey ? .greyscale : sampling == 0 ? .yuv444 : sampling == 1 ? .yuv422 : .yuv420,
                                progressiveMode: scan == 0 ? .sequential : scan == 1 ? .spectralSelection : .successiveApproximation,
                                floatInputPolicy: bits == 32 ? .normalisedClampedToUInt8 : .reject,
                                colourSpace: xyb ? .xybFromSRGB : .yCbCr,
                                alphaPolicy: nc == 4 ? .discardStraightAlpha : .reject,
                                sourceColourSpace: profile == "yCbCr" ? .yCbCr : .fromDescriptor)
                            let original = try JLIEncoder().encode(oldImage, configuration: oldOptions)
                            let migrated = try await SwiftJLI.Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: options))).encode(image)
                            guard Array(migrated.data) == original else { throw SwiftJLI.CodecError(.internalFailure, "Codestream differs: \(profile)/\(bits)/\(width)/\(sampling)/\(scan)") }
                            let oldPixels = try JLIDecoder().decode(from: original)
                            let decoded = try await SwiftJLI.Decoder().decode(migrated.data)
                            guard try decoded.image.storage.withUnsafeBytes({ Array($0) }) == oldPixels.data,
                                  migrated.report.alphaDiscarded == (nc == 4), migrated.report.copyEvents.isEmpty,
                                  migrated.report.pixelAllocationCount == 0,
                                  decoded.image.descriptor.components.count == (grey ? 1 : 3) else {
                                throw SwiftJLI.CodecError(.internalFailure, "Samples or report differ: \(profile)")
                            }
                            count += 1
                        }
                    }
                    print("{\"profile\":\"\(profile)\",\"bits\":\(bits),\"width\":\(width),\"codestreamsAndSamplesEqual\":true}")
                }
            }
        }
        print("{\"comparedCases\":\(count),\"passed\":true}")
    }
}
