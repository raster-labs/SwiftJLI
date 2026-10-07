// SPDX-License-Identifier: Apache-2.0
import Foundation
import JLISwift
import SwiftJLI
import Darwin

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw SwiftJLI.CodecError(.internalFailure, message) }
}
func emit(_ value: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
}
func image(_ bytes: [UInt8], components: [SwiftJLI.ComponentRole], colour: SwiftJLI.ColourInterpretation,
           signed: Bool = false, alpha: SwiftJLI.AlphaInterpretation = .absent) throws -> SwiftJLI.Image {
    let bps = signed ? 2 : 1, width = 3, height = 2, nc = components.count
    let p = try SwiftJLI.PlaneDescriptor(width: width, height: height, components: Array(0..<nc),
        sampleStride: bps, pixelStride: nc * bps, rowBytes: width * nc * bps, byteCount: bytes.count)
    let d = try SwiftJLI.ImageDescriptor(width: width, height: height,
        sampleType: signed ? .signedInteger : .unsignedInteger, storageBits: bps * 8,
        meaningfulBits: bps * 8, components: components, colour: colour, alpha: alpha, planes: [p])
    return try SwiftJLI.ImageDestination.allocate(descriptor: d).write { $0.copyBytes(from: bytes) }
}
@main struct ProfileAudit {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Audit failed: \(error)\n".utf8)); exit(1) }
    }
    static func run() async throws {
        let rgb: [UInt8] = [1,70,200, 19,160,33, 240,10,88, 50,99,120, 3,5,7, 255,254,253]
        let oldRGB = try JLIImage(width: 3, height: 2, pixelFormat: .uint8, colorModel: .rgb, data: rgb)
        let oldEncoder = JLIEncoder(), oldDecoder = JLIDecoder()
        let newEncoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy))
        let encodedRGB = try oldEncoder.encode(oldRGB)
        var rgba = [UInt8]()
        for i in 0..<6 { rgba.append(contentsOf: rgb[i * 3..<(i * 3 + 3)]); rgba.append(UInt8(i * 40)) }
        let oldRGBA = try JLIImage(width: 3, height: 2, pixelFormat: .uint8, colorModel: .rgba, data: rgba)
        let rgbaJPEG = try oldEncoder.encode(oldRGBA)
        try check(rgbaJPEG == encodedRGB, "Predecessor RGBA did not discard alpha as expected")
        let newRGBA = try image(rgba, components: [.red, .green, .blue, .alpha], colour: .rgb, alpha: .straight)
        do { _ = try await newEncoder.encode(newRGBA); throw SwiftJLI.CodecError(.internalFailure, "RGBA unexpectedly accepted") }
        catch let error as SwiftJLI.CodecError {
            try check(error.category == .unsupportedFeature, "Unexpected RGBA failure category")
            try emit(["profile": "RGBA8", "predecessorMatchesRGBBytes": true,
                "predecessorDropsAlpha": true, "successor": String(describing: error.category)])
        }
        let yuv = try JLIImage(width: 3, height: 2, pixelFormat: .uint8, colorModel: .yCbCr, data: rgb)
        let yuvJPEG = try oldEncoder.encode(yuv)
        let yuvDecoded = try oldDecoder.decode(from: yuvJPEG)
        try check(yuvDecoded.width == 3 && yuvDecoded.data.count == 18, "YCbCr predecessor encode/decode failed")
        let newYUV = try image(rgb, components: [.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")], colour: .unknown)
        do { _ = try await newEncoder.encode(newYUV); throw SwiftJLI.CodecError(.internalFailure, "YCbCr unexpectedly accepted") }
        catch let error as SwiftJLI.CodecError {
            try check(error.category == .unsupportedFeature, "Unexpected YCbCr failure category")
            try emit(["profile": "preconvertedYCbCr8", "predecessorEncodedBytes": yuvJPEG.count,
                "predecessorDecodedBytes": yuvDecoded.data.count, "successor": String(describing: error.category)])
        }
        let greyJPEG = try oldEncoder.encode(oldRGB, configuration: .init(chromaSubsampling: .yuv400))
        let grey = try oldDecoder.decode(from: greyJPEG)
        try check(grey.colorModel == .grayscale && grey.data.count == 6, "RGB-to-greyscale profile missing")
        try emit(["profile": "RGB8ToGreyscale", "predecessorOutputComponents": 1,
            "successor": "no equivalent chromaSubsampling enum case or conversion option"])
        let signedBytes: [UInt8] = [0,128, 255,255, 0,0, 255,127, 1,128, 1,0]
        let signed = try JLIImage(width: 3, height: 2, pixelFormat: .uint16, colorModel: .grayscale,
            data: signedBytes, isSigned: true)
        let signedJPEG = try oldEncoder.encode(signed, configuration: .init(lossless: true, losslessPrecision: 16))
        let signedDecoded = try oldDecoder.decode(from: signedJPEG)
        try check(signedDecoded.data == signedBytes && !signedDecoded.isSigned,
            "Predecessor signed provenance assumption changed")
        let newSigned = try image(signedBytes, components: [.grey], colour: .greyscale, signed: true)
        do { _ = try await SwiftJLI.Encoder().encode(newSigned); throw SwiftJLI.CodecError(.internalFailure, "Signed input unexpectedly accepted") }
        catch let error as SwiftJLI.CodecError {
            try check(error.category == .unsupportedFeature, "Unexpected signed failure category")
            try emit(["profile": "signedUInt16BitPatternLossless", "predecessorBytesEqual": true,
                "predecessorDecodedSignedFlag": signedDecoded.isSigned,
                "successor": String(describing: error.category)])
        }
        let ordinary = try oldDecoder.decode(from: encodedRGB)
        let relabelled = try oldDecoder.decode(from: encodedRGB, configuration: .init(outputColorModel: .yCbCr))
        try check(ordinary.data == relabelled.data && relabelled.colorModel == .yCbCr,
            "Predecessor output colour relabelling assumption changed")
        try emit(["profile": "outputColorModelYCbCr", "predecessorBytesUnchanged": true,
            "predecessorOnlyRelabelsRGB": true, "successor": "no unqualified relabelling option"])
    }
}
