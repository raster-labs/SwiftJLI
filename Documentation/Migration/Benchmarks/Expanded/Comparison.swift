// SPDX-License-Identifier: Apache-2.0
import Foundation
import JLISwift
import SwiftJLI
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now).components
    return Double(d.seconds) + Double(d.attoseconds) / 1e18
}
func statistics(_ samples: [Double], pixels: Int) -> [String: Any] {
    let sorted = samples.sorted(), n = samples.count
    let median = n % 2 == 0 ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2 : sorted[n / 2]
    return ["samplesSeconds": samples, "medianSeconds": median,
        "p95Seconds": sorted[Int(ceil(Double(n) * 0.95)) - 1],
        "minimumSeconds": sorted[0], "maximumSeconds": sorted[n - 1],
        "medianPixelsPerSecond": Double(pixels) / median]
}
func context() -> [String: Any] {
    var usage = rusage()
    #if canImport(Darwin)
    let ok = getrusage(RUSAGE_SELF, &usage)
    let rss = Int64(usage.ru_maxrss)
    let thermal = ProcessInfo.processInfo.thermalState.rawValue
    #else
    let ok = getrusage(RUSAGE_SELF.rawValue, &usage)
    let rss = Int64(usage.ru_maxrss) * 1024
    let thermal = -1
    #endif
    var load = [Double](repeating: 0, count: 3)
    let loadCount = getloadavg(&load, 3)
    return ["pairedProcessPeakRSSBytes": ok == 0 ? rss : -1,
        "thermalState": thermal, "loadAverage": loadCount == 3 ? load : [],
        "activeProcessors": ProcessInfo.processInfo.activeProcessorCount]
}
func emit(_ value: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
}
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw SwiftJLI.CodecError(.internalFailure, message) }
}

@main struct Benchmark {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("Benchmark failed: \(error)\n".utf8)); exit(1) }
    }
    @concurrent static func run() async throws {
        let smoke = CommandLine.arguments.contains("--smoke")
        let warmups = smoke ? 1 : 5, timed = smoke ? 1 : 20
        let sizes = smoke ? [65] : [512, 1024]
        try emit(["event": "start", "smoke": smoke, "warmups": warmups,
            "timedIterations": timed, "context": context(),
            "backendPolicy": "automatic on both implementations",
            "os": ProcessInfo.processInfo.operatingSystemVersionString])
        for size in sizes {
            for profile in ["lossless16", "dct12", "rgb8", "progressiveRGB8", "xyb8"] {
                let bits = profile == "lossless16" ? 16 : profile == "dct12" ? 12 : 8
                let nc = bits == 8 ? 3 : 1, bps = bits > 8 ? 2 : 1, row = size * nc * bps
                let xyb = profile == "xyb8", progressive = profile == "progressiveRGB8", lossless = bits == 16
                var bytes = [UInt8](repeating: 0, count: row * size)
                for y in 0..<size { for x in 0..<(size * nc) {
                    let v = (x * 17 + y * 31 + x * y % 257) & ((1 << bits) - 1), offset = y * row + x * bps
                    bytes[offset] = UInt8(truncatingIfNeeded: v)
                    if bps == 2 { bytes[offset + 1] = UInt8(v >> 8) }
                } }
                let legacy = try JLIImage(width: size, height: size, pixelFormat: bits == 8 ? .uint8 : .uint16,
                    colorModel: nc == 1 ? .grayscale : .rgb, data: bytes)
                let plane = try SwiftJLI.PlaneDescriptor(width: size, height: size, components: Array(0..<nc),
                    sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: bytes.count)
                let descriptor = try SwiftJLI.ImageDescriptor(width: size, height: size, storageBits: bps * 8,
                    meaningfulBits: bits, components: nc == 1 ? [.grey] : [.red, .green, .blue],
                    colour: nc == 1 ? .greyscale : .rgb, planes: [plane])
                let image = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor).write { $0.copyBytes(from: bytes) }
                let oldConfig = JLIEncoderConfiguration(chromaSubsampling: xyb ? .yuv444 : .yuv420,
                    colorSpace: xyb ? .xyb : .yCbCr, progressive: progressive, lossless: lossless,
                    losslessPrecision: lossless ? 16 : 0)
                let newConfig = try SwiftJLI.EncoderConfiguration(mode: lossless ? .lossless : .lossy,
                    codecOptions: lossless ? .init() : .init(dct: .init(chromaSubsampling: xyb ? .yuv444 : .yuv420,
                        progressiveMode: progressive ? .spectralSelection : .sequential,
                        colourSpace: xyb ? .xybFromSRGB : .yCbCr)))
                let oldEncoder = JLIEncoder(), oldDecoder = JLIDecoder()
                let encoder = try SwiftJLI.Encoder(configuration: newConfig), decoder = try SwiftJLI.Decoder()
                let limits = try SwiftJLI.ResourceLimits(maximumWorkspaceBytes: 1024 * 1024 * 1024)
                let encodeOptions = SwiftJLI.EncodeOptions(resourceLimits: limits)
                let oldJPEG = try oldEncoder.encode(legacy, configuration: oldConfig)
                let newJPEG = try await encoder.encode(image, options: encodeOptions)
                try check(oldJPEG == Array(newJPEG.data), "Codestream mismatch: \(profile)")
                let oldPixels = try oldDecoder.decode(from: oldJPEG)
                let newPixels = try await decoder.decode(newJPEG.data)
                try check(oldPixels.width == newPixels.image.descriptor.width &&
                    oldPixels.height == newPixels.image.descriptor.height &&
                    oldPixels.data == newPixels.image.storage.withUnsafeBytes { Array($0) },
                    "Decoded samples differ: \(profile)")
                if lossless { try check(oldPixels.data == bytes, "Lossless samples differ from input") }
                var oe: [Double] = [], ne: [Double] = [], od: [Double] = [], nd: [Double] = []
                oe.reserveCapacity(timed); ne.reserveCapacity(timed); od.reserveCapacity(timed); nd.reserveCapacity(timed)
                let before = context()
                var checksum: UInt64 = 0
                for i in 0..<(warmups + timed) {
                    for successor in i % 2 == 0 ? [false, true] : [true, false] {
                        var start = ContinuousClock.now
                        if successor {
                            let e = try await encoder.encode(image, options: encodeOptions); let t = elapsed(start)
                            checksum &+= UInt64(e.data.count); if i >= warmups { ne.append(t) }
                            start = .now
                            let d = try await decoder.decode(newJPEG.data); let dt = elapsed(start)
                            checksum &+= UInt64(d.image.storage.byteCount); if i >= warmups { nd.append(dt) }
                        } else {
                            let e = try oldEncoder.encode(legacy, configuration: oldConfig); let t = elapsed(start)
                            checksum &+= UInt64(e.count); if i >= warmups { oe.append(t) }
                            start = .now
                            let d = try oldDecoder.decode(from: oldJPEG); let dt = elapsed(start)
                            checksum &+= UInt64(d.data.count); if i >= warmups { od.append(dt) }
                        }
                    }
                }
                try emit(["event": "case", "profile": profile, "width": size, "height": size,
                    "bits": bits, "components": nc, "warmups": warmups, "timedIterations": timed,
                    "codestreamsEqual": true, "samplesEqual": true, "compressedBytes": oldJPEG.count,
                    "checksum": checksum, "before": before, "after": context(),
                    "successorEncodeBackend": String(describing: newJPEG.report.backend),
                    "successorDecodeBackend": String(describing: newPixels.report.backend),
                    "predecessorEncode": statistics(oe, pixels: size * size),
                    "successorEncode": statistics(ne, pixels: size * size),
                    "predecessorDecode": statistics(od, pixels: size * size),
                    "successorDecode": statistics(nd, pixels: size * size)])
            }
        }
        try emit(["event": "complete", "smoke": smoke, "context": context()])
    }
}
