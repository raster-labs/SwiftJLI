import Foundation
import SwiftJLI

@main struct ProfileDecode {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let seconds = Double(CommandLine.arguments[2]) ?? 12
        let decoder = try SwiftJLI.Decoder()
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
                                        maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let options = DecodeOptions(resourceLimits: limits)
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(seconds))
        var iterations = 0
        var checksum = 0
        while ContinuousClock.now < deadline {
            let result = try await decoder.decode(data, options: options)
            checksum &+= result.image.storage.byteCount
            iterations += 1
        }
        print("iterations=\(iterations) checksum=\(checksum) duration=\(start.duration(to: .now))")
    }
}
