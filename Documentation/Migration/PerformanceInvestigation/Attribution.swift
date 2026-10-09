@testable import JLISwift
import Foundation
@testable import SwiftJLI
import Darwin

@main struct Attribution {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        for size in [512, 1024] {
            let bytes: [UInt8] = (0..<(size * size)).flatMap { i in
                let v = (i * 17 + (i / size) * 31) & 65535
                return [UInt8(truncatingIfNeeded: v), UInt8(v >> 8)]
            }
            let oldImage = try OldImage(width: size, height: size, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
            let nativeImage = try SwiftJLI.JLIImage(width: size, height: size, pixelFormat: .uint16, colorModel: .grayscale, data: bytes)
            let image = try SwiftJLI.ImageDestination.allocate(descriptor: .greyscale16(width: size, height: size)).write { $0.copyBytes(from: bytes) }
            let encoder = try SwiftJLI.Encoder()
            let expected = try OldEncoder().encode(oldImage, configuration: .init(lossless: true, losslessPrecision: 16))
            let modes = ["predecessorParallel", "predecessorSerial", "nativeParallel", "nativeSerial", "nativeContext", "public"]
            var times = Dictionary(uniqueKeysWithValues: modes.map { ($0, [Double]()) })
            for iteration in 0..<25 {
                for mode in iteration % 2 == 0 ? modes : modes.reversed() {
                    OldEncoder.losslessParallelMinSamples = mode == "predecessorSerial" ? Int.max : 1 << 16
                    SwiftJLI.JLIEncoder.losslessParallelMinSamples = mode == "nativeSerial" ? Int.max : 1 << 16
                    let start = ContinuousClock.now
                    let result: [UInt8]
                    switch mode {
                    case "predecessorParallel", "predecessorSerial":
                        result = try OldEncoder().encode(oldImage, configuration: .init(lossless: true, losslessPrecision: 16))
                    case "nativeParallel", "nativeSerial":
                        result = try SwiftJLI.JLIEncoder().encode(nativeImage, configuration: .init(lossless: true, losslessPrecision: 16))
                    case "nativeContext":
                        result = try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120)) {
                            try SwiftJLI.JLIEncoder().encode(nativeImage, configuration: .init(lossless: true, losslessPrecision: 16))
                        }
                    default: result = Array(try await encoder.encode(image).data)
                    }
                    let duration = start.duration(to: .now).components
                    let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                    guard result == expected else { throw SwiftJLI.CodecError(.internalFailure, "Attribution output differs: \(mode)") }
                    if iteration >= 5 { times[mode, default: []].append(seconds) }
                }
            }
            var medians: [String: Double] = [:]
            for mode in modes {
                let sorted = times[mode]!.sorted()
                medians[mode] = (sorted[9] + sorted[10]) / 2
            }
            let output: [String: Any] = ["size": size, "samples": times, "medianSeconds": medians,
                "codestreamsEqual": true, "warmups": 5, "timedIterations": 20,
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "note": "Internal attribution probe built with enable-testing; not the public release acceptance benchmark."]
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
        }
    }
}
