import Foundation
import SwiftJLI
@main struct Race {
 static func main() async throws {
  let jpeg = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
  let decoder = try SwiftJLI.Decoder()
  let control = try await decoder.decode(jpeg, options:.init(resourceLimits:ResourceLimits(maximumWorkers:1)))
  let expected = try control.image.storage.withUnsafeBytes { Array($0) }
  try await withThrowingTaskGroup(of:Void.self) { group in
   for _ in 0..<4 {
    group.addTask {
     let result = try await decoder.decode(jpeg, options:.init(resourceLimits:ResourceLimits(maximumWorkers:4)))
     let actual = try result.image.storage.withUnsafeBytes { Array($0) }
     guard actual == expected else { throw NSError(domain:"PixelMismatch",code:1) }
    }
   }
   try await group.waitForAll()
  }
  print("PASS: four concurrent 257x257 decodes, four workers each, match the one-worker control")
 }
}
