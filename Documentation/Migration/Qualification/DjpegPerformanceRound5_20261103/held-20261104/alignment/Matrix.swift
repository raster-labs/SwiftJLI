import Foundation
import SwiftJLI

@main struct Matrix {
    static func main() async throws { try await run() }
    @concurrent static func run() async throws {
        let mode = CommandLine.arguments[1]
        let selectedCases = Set(CommandLine.arguments.dropFirst(3))
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        let sizes = [19, 512, 2048, 3072], patterns = ["flat", "ramp", "noise", "mixed"]
        let decoder = try SwiftJLI.Decoder()
        let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossless))
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
                                        maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let options = DecodeOptions(resourceLimits: limits)
        for pattern in patterns { for size in sizes {
            let stem = "\(pattern)-\(size)", jpegURL = directory.appendingPathComponent("\(stem).jpg")
            let rawURL = directory.appendingPathComponent("\(stem).raw")
            if !selectedCases.isEmpty && !selectedCases.contains(stem) { continue }
            if mode == "generate" {
                var bytes = [UInt8](repeating: 0, count: size * size * 2)
                var randomState: UInt64 = 0xC0DEC
                for y in 0..<size { for x in 0..<size {
                    randomState = randomState &* 6364136223846793005 &+ 1
                    let value: Int
                    switch pattern {
                    case "flat": value = 65535 / 2
                    case "ramp": value = ((x + y) * 65535 / max(1, 2 * (size - 1)))
                    case "noise": value = Int(truncatingIfNeeded: randomState >> 32) & 65535
                    default: value = (x * 17 + y * 31 + x * y % 257) & 65535
                    }
                    let offset = (y * size + x) * 2
                    bytes[offset] = UInt8(truncatingIfNeeded: value)
                    bytes[offset + 1] = UInt8(value >> 8)
                } }
                let descriptor = try ImageDescriptor.greyscale16(width: size, height: size)
                let source = try ImageDestination.allocate(descriptor: descriptor).write { $0.copyBytes(from: bytes) }
                let encoded = try await encoder.encode(source, options: .init(resourceLimits: limits))
                try encoded.data.write(to: jpegURL)
                try Data(bytes).write(to: rawURL)
                continue
            }
            let jpeg = try Data(contentsOf: jpegURL), expected = try Data(contentsOf: rawURL)
            do {
                let result = try await decoder.decode(jpeg, options: options)
                guard result.image.descriptor.width == size, result.image.descriptor.height == size,
                      try result.image.storage.withUnsafeBytes({ Data($0) }) == expected else {
                    throw CodecError(.internalFailure, "Exact verification failed for \(stem)")
                }
            }
            var samples: [Double] = [], checksum: UInt64 = 0
            for iteration in 0..<25 {
                let start = ContinuousClock.now
                let result = try await decoder.decode(jpeg, options: options)
                let duration = start.duration(to: .now).components
                let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                if iteration >= 5 { samples.append(seconds) }
                checksum += UInt64(try result.image.sampleUInt16(x: iteration % size, y: iteration % size))
            }
            let sorted = samples.sorted()
            let result: [String: Any] = ["case": stem, "samplesSeconds": samples,
                "medianSeconds": (sorted[9] + sorted[10]) / 2, "p95Seconds": sorted[18],
                "checksum": checksum, "pixelExact": true, "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "api": "SwiftJLI.Decoder.decode allocating destination; input read and exact verification outside timing"]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
        } }
    }
}
