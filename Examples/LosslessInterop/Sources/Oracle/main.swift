// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
@main struct Oracle {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        for bits in 2...16 { for predictor in 1...7 { for point in [0, min(2, bits - 1)] {
            let width = 13, height = 7, maxValue = (1 << bits) - 1
            func value(_ x: Int, _ y: Int) -> UInt16 {
                if x == 0 { return 0 }; if x == 1 { return UInt16(maxValue) }
                return UInt16(((x * 15731) ^ (y * 31957)) & maxValue)
            }
            let stem = "\(bits)-\(predictor)-pt\(point)"
            let descriptor = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: 32)
            if CommandLine.arguments[1] == "generate" {
                let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16(value)
                let encoder = try SwiftJLI.Encoder(configuration: .init(mode: point == 0 ? .lossless : .nearLossless(maximumAbsoluteError: (1 << point) - 1), codecOptions: .init(predictor: predictor, restartInterval: width * 2)))
                let encoded = try await encoder.encode(image)
                try encoded.data.write(to: root.appendingPathComponent("\(stem)-swift.jpg"))
                var pgm = Data("P5\n\(width) \(height)\n\(maxValue)\n".utf8)
                for y in 0..<height { for x in 0..<width {
                    let v = value(x, y)
                    if bits > 8 { pgm.append(UInt8(v >> 8)) }
                    pgm.append(UInt8(truncatingIfNeeded: v))
                } }
                try pgm.write(to: root.appendingPathComponent("\(stem).pgm"))
            } else {
                let data = try Data(contentsOf: root.appendingPathComponent("\(stem)-oracle.jpg"))
                let destination = try ImageDestination.allocate(descriptor: descriptor)
                let decoded = try await SwiftJLI.Decoder().decode(data, into: destination)
                for y in 0..<height { for x in 0..<width {
                    guard try decoded.image.sampleUInt16(x: x, y: y) == (value(x, y) >> point) << point else {
                        throw CodecError(.internalFailure, "Oracle sample mismatch at \(stem).")
                    }
                } }
            }
        } } }
        print("210 \(CommandLine.arguments[1]) cases passed")
    }
}
