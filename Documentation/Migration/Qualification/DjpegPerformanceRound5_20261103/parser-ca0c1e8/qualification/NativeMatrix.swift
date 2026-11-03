import Foundation
import CryptoKit
import SwiftJLI

@main struct NativeMatrix {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let input = try Data(contentsOf: url)
        let decoder = try SwiftJLI.Decoder()
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
                                        maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let options = DecodeOptions(resourceLimits: limits)
        let checked = try await decoder.decode(input, options: options)
        let output = try checked.image.storage.withUnsafeBytes { Data($0) }
        let lossless = CommandLine.arguments.count == 3
        if lossless {
            let expected = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            guard output == expected else { throw CodecError(.internalFailure, "Full lossless output differs from source") }
        }
        let digest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
        let batch = lossless && checked.image.descriptor.width == 19 ? 500 : 1
        var times: [Double] = []
        var checksum: UInt64 = 0
        for index in 0..<25 {
            if batch == 1 {
                let start = ContinuousClock.now
                let decoded = try await decoder.decode(input, options: options)
                let duration = start.duration(to: .now).components
                if index >= 5 { times.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18) }
                checksum &+= UInt64(decoded.image.storage.byteCount)
                withExtendedLifetime(decoded) {}
            } else {
                let start = ContinuousClock.now
                for _ in 0..<batch {
                    let decoded = try await decoder.decode(input, options: options)
                    checksum &+= UInt64(decoded.image.storage.byteCount)
                    withExtendedLifetime(decoded) {}
                }
                let duration = start.duration(to: .now).components
                if index >= 5 { times.append((Double(duration.seconds) + Double(duration.attoseconds) / 1e18) / Double(batch)) }
            }
        }
        let sorted = times.sorted()
        let result: [String: Any] = ["fixture": url.lastPathComponent, "samplesSeconds": times,
            "medianSeconds": (sorted[9] + sorted[10]) / 2, "p95Seconds": sorted[18],
            "outputSHA256": digest, "outputBytes": output.count,
            "width": checked.image.descriptor.width, "height": checked.image.descriptor.height,
            "sourceExact": lossless, "decodesPerSample": batch, "checksum": checksum,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}
