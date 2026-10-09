import Foundation
@testable import JLISwift
@testable import SwiftJLI

@main struct Probe {
    static func main() throws {
        for width in [512, 2048] {
            let height = width
            var bytes = [UInt8](repeating: 0, count: width * height * 3)
            for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i * 73 + i / (width * 3) * 19) }
            let expected = OldDSP.imageRGBToYCbCr(data: bytes, pixelCount: width * height, componentCount: 3)
            var samples: [String: [Double]] = ["predecessor": [], "borrowed": []]
            for iteration in 0..<25 {
                for name in iteration % 2 == 0 ? ["predecessor", "borrowed"] : ["borrowed", "predecessor"] {
                    let start = ContinuousClock.now
                    let result: (y: [Float], cb: [Float], cr: [Float])
                    if name == "predecessor" {
                        result = OldDSP.imageRGBToYCbCr(data: bytes, pixelCount: width * height, componentCount: 3)
                    } else {
                        result = try SwiftJLI.NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: 8)) {
                            try bytes.withUnsafeBytes {
                                try SwiftJLI.SharedDCTStorage.read(.init(bytes: $0, rowBytes: width * 3),
                                    width: width, height: height, components: 3, precision: 8)
                            }
                        }
                    }
                    let d = start.duration(to: .now).components
                    guard result.y == expected.y && result.cb == expected.cb && result.cr == expected.cr else {
                        throw SwiftJLI.CodecError(.internalFailure, "Input planes differ")
                    }
                    if iteration >= 5 { samples[name, default: []].append(Double(d.seconds) + Double(d.attoseconds) / 1e18) }
                }
            }
            var medians: [String: Double] = [:]
            for (name, values) in samples { let s = values.sorted(); medians[name] = (s[9] + s[10]) / 2 }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["width": width, "height": height,
                "samplesSeconds": samples, "medianSeconds": medians, "planesEqual": true,
                "warmups": 5, "timedIterations": 20, "thermalState": ProcessInfo.processInfo.thermalState.rawValue], options: .sortedKeys), as: UTF8.self))
        }
    }
}
