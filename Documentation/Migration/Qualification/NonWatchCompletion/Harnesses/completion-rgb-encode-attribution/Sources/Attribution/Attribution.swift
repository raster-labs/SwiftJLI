import Foundation
@testable import SwiftJLI
@main struct Attribution {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        for size in [19, 512] { for pattern in ["flat", "ramp"] {
            let bytes: [UInt8] = (0..<(size * size * 3)).map { i in
                let x = (i % (size * 3)) / 3, y = i / (size * 3)
                return UInt8(pattern == "flat" ? 127 : (x + y) * 255 / max(1, 2 * (size - 1)))
            }
            let old = try OldImage(width: size, height: size, pixelFormat: .uint8, colorModel: .rgb, data: bytes)
            let native = try JLIImage(width: size, height: size, pixelFormat: .uint8, colorModel: .rgb, data: bytes)
            let plane = try PlaneDescriptor(width: size, height: size, components: [0, 1, 2], sampleStride: 1, pixelStride: 3, rowBytes: size * 3, byteCount: size * size * 3)
            let descriptor = try ImageDescriptor(width: size, height: size, storageBits: 8, meaningfulBits: 8, components: [.red, .green, .blue], colour: .rgb, planes: [plane])
            let image = try ImageDestination.allocate(descriptor: descriptor).write { $0.copyBytes(from: bytes) }
            let expected = try OldEncoder().encode(old, configuration: OldConfiguration())
            let encoder = try Encoder(configuration: .init(mode: .lossy))
            let modes = ["predecessor", "native", "contextNative", "shared", "public"]
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
                                    return try JLIEncoder().encodeSharedDCT(from: .init(bytes: raw, rowBytes: size * 3), width: size, height: size, precision: 8, components: 3, icc: nil, exif: nil, configuration: .init())
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
            let output: [String: Any] = ["size": size, "pattern": pattern, "samples": times, "medianSeconds": medians,
                "codestreamsEqual": true, "warmups": 5, "timedIterations": 20,
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "note": "Internal enable-testing attribution; not public release acceptance."]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
        } }
    }
}
