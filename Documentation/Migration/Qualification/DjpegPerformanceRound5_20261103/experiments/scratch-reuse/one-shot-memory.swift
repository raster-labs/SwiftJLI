import Foundation
import SwiftJLI

// A single public decode keeps the input and one final output allocation alive.
// Full byte equality is checked separately by the paired native benchmark.
@main struct MemoryProbe {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        guard CommandLine.arguments.count == 3,
              let workers = Int(CommandLine.arguments[2]), workers > 0 else {
            throw NSError(domain: "MemoryProbeArguments", code: 1)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
            maximumWorkers: workers, maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let decoder = try SwiftJLI.Decoder()
        let decoded = try await decoder.decode(data, options: .init(resourceLimits: limits))
        let sample = try decoded.image.storage.withUnsafeBytes { bytes in
            bytes.isEmpty ? 0 : Int(bytes[0]) + Int(bytes[bytes.count - 1])
        }
        print("\(decoded.image.storage.byteCount) \(sample)")
        withExtendedLifetime(decoded) {}
    }
}
