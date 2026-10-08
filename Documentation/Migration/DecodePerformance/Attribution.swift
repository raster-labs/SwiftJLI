import Foundation
@testable import JLISwift
@testable import SwiftJLI

@main struct Attribution {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        for size in [512, 1024] { for profile in ["grey12", "rgb8", "progressiveRGB8"] {
            let nc = profile == "grey12" ? 1 : 3, bits = nc == 1 ? 12 : 8, bps = nc == 1 ? 2 : 1
            var bytes = [UInt8](repeating: 0, count: size * size * nc * bps)
            for i in 0..<(size * size * nc) {
                let x = i % (size * nc), y = i / (size * nc)
                let v = (x * 17 + y * 31 + x * y % 257) & ((1 << bits) - 1)
                bytes[i * bps] = UInt8(truncatingIfNeeded: v)
                if bps == 2 { bytes[i * bps + 1] = UInt8(v >> 8) }
            }
            let oldImage = try OldImage(width: size, height: size, pixelFormat: bps == 2 ? .uint16 : .uint8,
                colorModel: nc == 1 ? .grayscale : .rgb, data: bytes)
            let jpeg = try OldEncoder().encode(oldImage, configuration: .init(progressive: profile == "progressiveRGB8"))
            let data = Data(jpeg), expected = try OldDecoder().decode(from: jpeg).data
            var reader = SwiftJLI.MarkerReader(data: jpeg)
            let parsed = try reader.parse()
            let modes = ["nativeParsedContext", "borrowedParsedContext", "predecessorFull", "nativeFull", "nativeContextFull", "publicFull", "nativeParse", "validatedParse", "envelope"]
            var times = Dictionary(uniqueKeysWithValues: modes.map { ($0, [Double]()) })
            var checksum = 0
            for iteration in 0..<25 {
                for mode in iteration % 2 == 0 ? modes : modes.reversed() {
                    var output: [UInt8]? = nil
                    var publicOutput: SwiftJLI.DecodedImage? = nil
                    let start = ContinuousClock.now
                    switch mode {
                    case "predecessorFull": output = try OldDecoder().decode(from: jpeg).data
                    case "nativeFull": output = try SwiftJLI.JLIDecoder().decode(from: jpeg).data
                    case "nativeParsedContext":
                        output = try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                            try SwiftJLI.JLIDecoder().decodeParsed(parsed).data
                        }
                    case "borrowedParsedContext":
                        output = try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                            var pixels = [UInt8](repeating: 0, count: expected.count)
                            try pixels.withUnsafeMutableBytes { raw in
                                _ = try SwiftJLI.JLIDecoder().decodeParsed(parsed,
                                    borrowedDestination: .init(bytes: raw, rowBytes: size * nc * bps, bytesPerSample: bps))
                            }
                            return pixels
                        }
                    case "nativeContextFull":
                        output = try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                            try SwiftJLI.JLIDecoder().decode(from: jpeg).data
                        }
                    case "publicFull": publicOutput = try await SwiftJLI.Decoder().decode(data)
                    case "nativeParse":
                        var reader = SwiftJLI.MarkerReader(data: jpeg)
                        checksum += try reader.parse().scans.count
                    case "validatedParse":
                        checksum += try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                            try SwiftJLI.JPEGCodec.parse(data, options: .init()).scans.count
                        }
                    default:
                        checksum += Int(try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120)) {
                            try SwiftJLI.JPEGEnvelope.validate(jpeg, limits: .default)
                        } ?? 0)
                    }
                    let duration = start.duration(to: .now).components
                    let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                    if let output { guard output == expected else { throw SwiftJLI.CodecError(.internalFailure, "Samples differ: \(mode)") } }
                    if let publicOutput {
                        guard try publicOutput.image.storage.withUnsafeBytes({ Array($0) }) == expected else {
                            throw SwiftJLI.CodecError(.internalFailure, "Public samples differ")
                        }
                    }
                    if iteration >= 5 { times[mode, default: []].append(seconds) }
                }
            }
            var medians: [String: Double] = [:]
            for mode in modes { let sorted = times[mode]!.sorted(); medians[mode] = (sorted[9] + sorted[10]) / 2 }
            let result: [String: Any] = ["size": size, "profile": profile, "samplesSeconds": times, "medianSeconds": medians,
                "samplesEqual": true, "checksum": checksum, "warmups": 5, "timedIterations": 20,
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
        } }
    }
}
