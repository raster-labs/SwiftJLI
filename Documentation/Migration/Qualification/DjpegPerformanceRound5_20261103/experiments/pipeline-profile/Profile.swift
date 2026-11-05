import Foundation
import CryptoKit
import SwiftJLI

@main struct Profile {
    static func main() async throws { try await run() }

    @concurrent static func run() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let workers = Int(CommandLine.arguments[2]), workers > 0,
              let seconds = Double(CommandLine.arguments[3]), seconds > 0 else {
            throw CocoaError(.coderInvalidValue)
        }
        let data = try Data(contentsOf: fixture)
        let decoder = try SwiftJLI.Decoder()
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
            maximumWorkers: workers, maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let options = DecodeOptions(resourceLimits: limits)
        func digest(_ image: Image) throws -> String {
            try image.storage.withUnsafeBytes {
                SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined()
            }
        }
        let expected = try digest(try await decoder.decode(data, options: options).image)
        for _ in 0..<5 { _ = try await decoder.decode(data, options: options) }
        FileHandle.standardOutput.write(Data(("READY " + expected + "\n").utf8))
        let started = ContinuousClock.now
        var iterations = 0, checksum = 0
        while true {
            let elapsed = started.duration(to: .now).components
            if Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18 >= seconds { break }
            let decoded = try await decoder.decode(data, options: options)
            checksum &+= decoded.image.storage.byteCount
            iterations += 1
        }
        let actual = try digest(try await decoder.decode(data, options: options).image)
        guard actual == expected else { throw CocoaError(.coderInvalidValue) }
        let report: [String: Any] = ["fixture": fixture.path, "workers": workers,
            "outputSHA256": actual, "iterations": iterations, "checksum": checksum,
            "profileDurationSeconds": seconds, "firstLastOutputExact": true,
            "note": "Sampling diagnostic only; not a benchmark result."]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report,
            options: [.sortedKeys]))
        FileHandle.standardOutput.write(Data([10]))
    }
}
