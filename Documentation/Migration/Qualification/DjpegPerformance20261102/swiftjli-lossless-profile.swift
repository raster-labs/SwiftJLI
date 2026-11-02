import Foundation
import SwiftJLI

@main struct Profile {
    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let iterations = Int(CommandLine.arguments[2])!
        let decoder = try SwiftJLI.Decoder()
        var checksum: UInt64 = 0
        let start = ContinuousClock.now
        for index in 0..<iterations {
            let result = try await decoder.decode(data)
            checksum += UInt64(try result.image.sampleUInt16(x: index % 2048, y: index % 2048))
        }
        print("iterations=\(iterations) elapsed=\(start.duration(to: .now)) checksum=\(checksum)")
    }
}
