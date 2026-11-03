import Foundation
import SwiftJLI
@main struct LargeDCTOracle {
    static func main() async throws {
        guard CommandLine.arguments.count == 4, let restart = Int(CommandLine.arguments[3]),
              [3, 1023].contains(restart), ["generate-dct", "verify-dct"].contains(CommandLine.arguments[1]) else {
            throw CodecError(.invalidArgument, "Expected command, directory and restart interval")
        }
        try await DCTOracle.run(CommandLine.arguments[1], root: URL(fileURLWithPath: CommandLine.arguments[2]), restart: restart)
    }
}
