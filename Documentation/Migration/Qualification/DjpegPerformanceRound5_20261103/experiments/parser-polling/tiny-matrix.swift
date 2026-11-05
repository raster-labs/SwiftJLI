import Foundation
import SwiftJLI

@main struct TinyMatrix {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw CodecError(.invalidArgument, "Expected fixture directory") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = try SwiftJLI.Decoder()
        for pattern in ["flat", "ramp", "noise", "mixed"] {
            let stem = "\(pattern)-19"
            let input = try Data(contentsOf: directory.appendingPathComponent(stem + ".jpg"))
            let expected = try Data(contentsOf: directory.appendingPathComponent(stem + ".raw"))
            let checked = try await decoder.decode(input)
            guard try checked.image.storage.withUnsafeBytes({ Data($0) }) == expected else {
                throw CodecError(.internalFailure, "Unexpected samples")
            }
            var samples: [Double] = [], checksum: UInt64 = 0
            for sample in 0..<25 {
                let start = ContinuousClock.now
                for _ in 0..<500 {
                    let decoded = try await decoder.decode(input)
                    checksum &+= UInt64(decoded.image.storage.byteCount)
                    withExtendedLifetime(decoded) {}
                }
                let duration = start.duration(to: .now).components
                let elapsed = (Double(duration.seconds) + Double(duration.attoseconds) / 1e18) / 500
                if sample >= 5 { samples.append(elapsed) }
            }
            let sorted = samples.sorted()
            let record: [String: Any] = ["case": stem, "samplesSecondsPerDecode": samples,
                "medianSeconds": (sorted[9]+sorted[10])/2, "p95Seconds": sorted[18],
                "decodesPerSample": 500, "warmupSamples": 5, "measuredSamples": 20,
                "checksum": checksum, "pixelExact": true,
                "method": "500 public allocated-output decodes per sample; allocation, decode and release included; input read and full-byte verification outside timing"]
            print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), as: UTF8.self))
        }
    }
}
