import Foundation
@testable import SwiftJLI
@main struct Attribution {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        for size in [512, 1024] {
            let bytes: [UInt8] = (0..<(size * size)).flatMap { i in
                let x = i % size, y = i / size, v = (x * 17 + y * 31 + x * y % 257) & 4095
                return [UInt8(truncatingIfNeeded: v), UInt8(v >> 8)]
            }
            let old = try OldImage(width: size, height: size, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
            let native = try JLIImage(width: size, height: size, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
            let image = try ImageDestination.allocate(descriptor: .greyscale16(width: size, height: size, meaningfulBits: 12)).write { $0.copyBytes(from: bytes) }
            let expected = try OldEncoder().encode(old, configuration: OldConfiguration())
            let encoder = try Encoder(configuration: .init(mode: .lossy))
            let modes = ["predecessor", "native", "contextNative", "shared", "sharedPreflight", "public"]
            var times = Dictionary(uniqueKeysWithValues: modes.map { ($0, [Double]()) })
            for iteration in 0..<25 {
                for mode in iteration % 2 == 0 ? modes : modes.reversed() {
                    let start = ContinuousClock.now
                    var result: [UInt8] = []
                    var publicResult: Data?
                    if mode == "predecessor" { result = try OldEncoder().encode(old, configuration: OldConfiguration()) }
                    else if mode == "native" { result = try JLIEncoder().encode(native) }
                    else if mode == "public" { publicResult = try await encoder.encode(image).data }
                    else {
                        result = try await NativeOperation.withCancellation {
                            try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                                if mode == "contextNative" { return try JLIEncoder().encode(native) }
                                return try image.storage.withUnsafeBytes { raw in
                                    if mode == "sharedPreflight" {
                                        for y in 0..<size {
                                            try NativeOperation.check()
                                            for x in 0..<size {
                                                let offset = (y * size + x) * 2
                                                guard UInt32(raw[offset]) | UInt32(raw[offset + 1]) << 8 < 4096 else {
                                                    throw CodecError(.invalidArgument, "Sample exceeds declared meaningful precision")
                                                }
                                            }
                                        }
                                    }
                                    return try JLIEncoder().encodeSharedDCT(from: .init(bytes: raw, rowBytes: size * 2), width: size, height: size, precision: 12, components: 1, icc: nil, exif: nil, configuration: .init())
                                }
                            }
                        }
                    }
                    let d = start.duration(to: .now).components
                    let elapsed = Double(d.seconds) + Double(d.attoseconds) / 1e18
                    if let publicResult { result = Array(publicResult) }
                    guard result == expected else { throw CodecError(.internalFailure, "DCT attribution identity mismatch: \(mode)") }
                    if iteration >= 5 { times[mode, default: []].append(elapsed) }
                }
            }
            let medians = times.mapValues { values in let s = values.sorted(); return (s[9] + s[10]) / 2 }
            let output: [String: Any] = ["size": size, "samples": times, "medianSeconds": medians,
                "codestreamsEqual": true, "warmups": 5, "timedIterations": 20,
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "note": "Internal enable-testing attribution; not public release acceptance."]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
        }
    }
}
