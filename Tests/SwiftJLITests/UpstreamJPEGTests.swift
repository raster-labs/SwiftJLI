// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import SwiftJLI

private func upstream(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext,
                                            subdirectory: "Fixtures/UpstreamJPEG"))
    return try Data(contentsOf: url)
}

@Suite struct UpstreamJPEGTests {
    @Test(arguments: ["monkey12-444", "monkey12-444-progressive", "testorig-444",
                      "testorig-444-progressive", "testimgint-444", "testimgint-444-progressive"])
    func independentNaturalTextureOracle(_ name: String) async throws {
        let encoded = try upstream(name, "jpg")
        let reference = try upstream(name + "-oracle", "pnm")
        var position = reference.startIndex
        var header: [String] = []
        for _ in 0..<3 {
            let end = try #require(reference[position...].firstIndex(of: 10))
            header.append(String(decoding: reference[position..<end], as: UTF8.self))
            position = reference.index(after: end)
        }
        let dimensions = header[1].split(separator: " ").compactMap { Int($0) }
        try #require(header[0] == "P6" && dimensions.count == 2)
        let maximum = try #require(Int(header[2]))
        let bps = maximum == 255 ? 1 : 2
        let bits = maximum == 255 ? 8 : 12
        try #require(reference.count - position == dimensions[0] * dimensions[1] * 3 * bps)
        let decoder = try SwiftJLI.Decoder()
        for policy: ExecutionPolicy in [.scalarCPU, .automatic] {
            let result = try await decoder.decode(encoded, options: .init(executionPolicy: policy))
            let d = result.image.descriptor
            try #require(d.width == dimensions[0] && d.height == dimensions[1])
            try #require(d.meaningfulBits == bits && d.components == [.red, .green, .blue])
            let error = try result.image.storage.withUnsafeBytes { actual -> Int in
                var error = 0
                for y in 0..<d.height { for x in 0..<(d.width * 3) {
                    let a = d.planes[0].offset + y * d.planes[0].rowBytes + x * bps
                    let b = position + (y * d.width * 3 + x) * bps
                    let ours = Int(actual[a]) | (bps == 2 ? Int(actual[a + 1]) << 8 : 0)
                    let oracle = bps == 1 ? Int(reference[b]) : Int(reference[b]) << 8 | Int(reference[b + 1])
                    error = max(error, abs(ours - oracle))
                } }
                return error
            }
            // Fixed existing DCT oracle limits; never inferred from this result.
            #expect(error <= (bits == 8 ? 2 : 4))
        }
    }

    @Test func validArithmeticCodingIsExplicitlyUnsupported() async throws {
        let data = try upstream("testimgari", "jpg")
        do {
            _ = try await SwiftJLI.Decoder().decode(data)
            Issue.record("Arithmetic JPEG must not be silently accepted")
        } catch let error as CodecError {
            #expect(error.category == .unsupportedFeature)
        }
    }

    @Test func upstreamTwelveBitICCIsPreservedEvenWhenAncillaryMetadataIsDiscarded() async throws {
        let data = try upstream("monkey12", "jpg")
        let profile = try upstream("sRGB2014", "icc")
        let decoder = try SwiftJLI.Decoder()
        let info = try decoder.inspect(data)
        #expect(info.descriptor.meaningfulBits == 12)
        #expect(info.descriptor.iccProfile == profile)
        let result = try await decoder.decode(data, options: .init(metadataPolicy: .discardAncillary))
        #expect(result.image.descriptor.iccProfile == profile)
        #expect(result.image.descriptor.components == [.red, .green, .blue])
    }
}
