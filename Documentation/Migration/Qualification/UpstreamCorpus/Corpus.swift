import Foundation
import JLISwift
import SwiftJLI

@main struct Corpus {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = try SwiftJLI.Decoder()
        for name in ["monkey12", "testimgint", "testorig"].flatMap({ [$0, $0 + "-444", $0 + "-444-progressive"] }) + ["testimgari"] {
            let data = try Data(contentsOf: root.appendingPathComponent(name + ".jpg"))
            if name == "testimgari" {
                do {
                    _ = try await decoder.decode(data)
                    throw SwiftJLI.CodecError(.internalFailure, "Arithmetic JPEG unexpectedly succeeded")
                } catch let error as SwiftJLI.CodecError {
                    guard error.category == .unsupportedFeature else { throw error }
                    print("PASS arithmetic coding rejected as unsupportedFeature")
                }
                continue
            }
            let old = try JLIDecoder().decode(from: Array(data))
            let result = try await decoder.decode(data)
            let d = result.image.descriptor
            let bytes = try result.image.storage.withUnsafeBytes { Array($0) }
            guard old.data == bytes else { throw SwiftJLI.CodecError(.internalFailure, "Predecessor sample mismatch: \(name)") }
            let channels = d.components.count, bps = d.storageBits / 8
            var pnm = Data("\(channels == 1 ? "P5" : "P6")\n\(d.width) \(d.height)\n\((1 << d.meaningfulBits) - 1)\n".utf8)
            for y in 0..<d.height { for x in 0..<(d.width * channels) {
                let p = d.planes[0].offset + y * d.planes[0].rowBytes + x * bps
                if bps == 2 { pnm.append(bytes[p + 1]) }; pnm.append(bytes[p])
            } }
            try pnm.write(to: root.appendingPathComponent(name + "-swift.pnm"))
            let details = try decoder.inspectJPEG(data)
            print("PASS \(name): predecessor samples exact; \(d.width)x\(d.height), \(d.meaningfulBits)-bit, \(details.chromaSubsampling)")
        }
    }
}
