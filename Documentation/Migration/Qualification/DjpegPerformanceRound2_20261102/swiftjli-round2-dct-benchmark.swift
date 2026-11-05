import Foundation
import CryptoKit
import SwiftJLI
@main struct Benchmark {
 static func main() async throws { try await run() }
 @concurrent static func run() async throws {
  let url = URL(fileURLWithPath: CommandLine.arguments[1])
  let data = try Data(contentsOf: url)
  let decoder = try SwiftJLI.Decoder()
  let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024, maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
  let options = DecodeOptions(resourceLimits: limits)
  let checked = try await decoder.decode(data, options: options)
  let output = try checked.image.storage.withUnsafeBytes { Data($0) }
  let digest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
  var times: [Double] = []
  var checksum = 0
  for index in 0..<25 {
   let start = ContinuousClock.now
   let decoded = try await decoder.decode(data, options: options)
   let duration = start.duration(to: .now).components
   if index >= 5 { times.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18) }
   checksum += decoded.image.storage.byteCount
  }
  let sorted = times.sorted()
  let result: [String: Any] = ["fixture": url.lastPathComponent, "samplesSeconds": times, "medianSeconds": (sorted[9]+sorted[10])/2, "p95Seconds": sorted[18], "outputSHA256": digest, "outputBytes": output.count, "checksum": checksum]
  print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
 }
}
