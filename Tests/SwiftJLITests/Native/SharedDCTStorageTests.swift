// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct SharedDCTStorageTests {
    @Test(arguments: [8, 12], [1, 3])
    func borrowedPixelsMatchPackedKernels(precision: Int, components: Int) throws {
        for backend: Backend in [.scalarCPU, .accelerated] {
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend)) {
                for subsampling: JLIChromaSubsampling in [.yuv444, .yuv422, .yuv420] {
                    for script in 0...2 {
                        let w = 19, h = 17, bps = precision == 8 ? 1 : 2
                        let payload = w * components * bps, rowBytes = payload + 7
                        var packed = [UInt8](repeating: 0, count: payload * h)
                        var padded = [UInt8](repeating: 0xA5, count: rowBytes * h)
                        for y in 0..<h { for x in 0..<(w * components) {
                            let value = (x * 173 + y * 259 + x * y * 13) & ((1 << precision) - 1)
                            for byte in 0..<bps {
                                let v = UInt8(truncatingIfNeeded: value >> (byte * 8))
                                packed[y * payload + x * bps + byte] = v
                                padded[y * rowBytes + x * bps + byte] = v
                            }
                        } }
                        let image = try JLIImage(width: w, height: h, pixelFormat: precision == 8 ? .uint8 : .uint16,
                            colorModel: components == 1 ? .grayscale : .rgb, data: packed)
                        let cfg = JLIEncoderConfiguration(quality: 87, chromaSubsampling: subsampling,
                            progressive: script > 0, progressiveMode: script == 2 ? .successiveApproximation : .spectralSelection,
                            restartInterval: 3)
                        let expected = try JLIEncoder().encode(image, configuration: cfg)
                        let actual = try padded.withUnsafeBytes { raw in
                            try JLIEncoder().encodeSharedDCT(from: .init(bytes: raw, rowBytes: rowBytes),
                                width: w, height: h, precision: precision, components: components,
                                icc: nil, exif: nil, configuration: cfg)
                        }
                        #expect(actual == expected, "Encode: \(precision), \(components), \(script), \(backend)")
                        var parser = MarkerReader(data: actual)
                        let parsed = try parser.parse()
                        for scale in [1, 2, 4, 8] {
                            let dc = JLIDecoderConfiguration(scale: scale)
                            let decoded = try JLIDecoder().decode(from: actual, configuration: dc)
                            let outW = (w + scale - 1) / scale, outH = (h + scale - 1) / scale
                            let outPayload = outW * components * bps, stride = outPayload + 11
                            var output = [UInt8](repeating: 0x5A, count: stride * outH)
                            try output.withUnsafeMutableBytes { raw in
                                _ = try JLIDecoder().decodeParsed(parsed, configuration: dc,
                                    borrowedDestination: .init(bytes: raw, rowBytes: stride, bytesPerSample: bps))
                            }
                            var result: [UInt8] = []
                            for y in 0..<outH {
                                result += output[(y * stride)..<(y * stride + outPayload)]
                                #expect(output[(y * stride + outPayload)..<((y + 1) * stride)].allSatisfy { $0 == 0x5A })
                            }
                            #expect(result == decoded.data, "Decode: \(precision), \(components), \(script), \(scale), \(backend)")
                        }
                        #expect(padded.enumerated().allSatisfy { $0.offset % rowBytes < payload || $0.element == 0xA5 })
                    }
                }
            }
        }
    }
}
