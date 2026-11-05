// SPDX-License-Identifier: Apache-2.0
// Public-API qualification of the two pinned 8-bit 4:2:0 benchmark fixtures.
import CryptoKit
import Darwin
import Foundation
import SwiftJLI

@main struct SubsampledRGBQualification {
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CodecError(.internalFailure, message) }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Qualification failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let arguments = CommandLine.arguments
        try require(arguments.count == 3, "Expected fixture and oracle directories")
        let fixtures = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let references = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let header = Data("P6\n512 512\n255\n".utf8)
        var records = [[String: Any]]()
        for stem in ["rgb8-512", "progressiveRGB8-512"] {
            let input = try Data(contentsOf: fixtures.appendingPathComponent(stem + ".jpg"))
            let decoder = try SwiftJLI.Decoder()
            let jpeg = try decoder.inspectJPEG(input)
            let descriptor = jpeg.imageInfo.descriptor
            try require(descriptor.width == 512 && descriptor.height == 512
                && descriptor.meaningfulBits == 8 && descriptor.storageBits == 8
                && descriptor.colour == .rgb && descriptor.components == [.red, .green, .blue]
                && jpeg.chromaSubsampling == .yuv420, "Pinned subsampled profile changed")
            var scalarSamples: Data?
            let rowBytes = descriptor.width * 3 + 7, offset = 5
            let plane = try PlaneDescriptor(width: descriptor.width, height: descriptor.height,
                components: [0, 1, 2], offset: offset, sampleStride: 1,
                pixelStride: 3, rowBytes: rowBytes, byteCount: rowBytes * descriptor.height)
            let padded = try ImageDescriptor(width: descriptor.width, height: descriptor.height,
                storageBits: 8, meaningfulBits: 8, components: [.red, .green, .blue],
                colour: .rgb, planes: [plane])
            for (backend, policy) in [("scalar", ExecutionPolicy.scalarCPU), ("automatic", .automatic)] {
                var firstSamples: Data?
                let baseline = try Data(contentsOf: references.appendingPathComponent("baseline-\(stem)-\(backend).pnm"))
                try require(baseline.starts(with: header) && baseline.count == header.count + 512 * 512 * 3,
                    "Baseline layout differs")
                for borrowed in [false, true] {
                    let destination = try ImageDestination.allocate(descriptor: padded)
                    let options = DecodeOptions(executionPolicy: policy)
                    let result = borrowed
                        ? try await decoder.decode(input, into: destination, options: options)
                        : try await decoder.decode(input, options: options)
                    let p = result.image.descriptor.planes[0]
                    var samples = Data()
                    try result.image.storage.withUnsafeBytes { bytes in
                        if borrowed {
                            try require(bytes.prefix(offset).allSatisfy { $0 == 0 }, "Prefix overwritten")
                        }
                        for y in 0..<descriptor.height {
                            let start = p.offset + y * p.rowBytes
                            samples.append(contentsOf: bytes[start..<(start + descriptor.width * 3)])
                            if borrowed {
                                let end = min(bytes.count, p.offset + (y + 1) * p.rowBytes)
                                try require(bytes[(start + descriptor.width * 3)..<end].allSatisfy { $0 == 0 },
                                    "Row padding overwritten")
                            }
                        }
                    }
                    if borrowed {
                        try require(result.image.storage.allocationID == destination.storage.allocationID,
                            "Caller allocation identity changed")
                        try require(result.report.pixelAllocationCount == 0 && result.report.copyEvents.isEmpty,
                            "Caller storage reported a pixel allocation or copy")
                    }
                    if let firstSamples {
                        try require(samples == firstSamples, "Allocating and caller destination samples differ")
                    } else { firstSamples = samples }
                    if backend == "scalar" { scalarSamples = samples }
                    let scalarDifference = zip(samples, scalarSamples ?? samples).map { abs(Int($0) - Int($1)) }.max() ?? 0
                    let pnm = header + samples
                    try require(pnm == baseline, "Output differs from pinned baseline on the same backend")
                    for version in ["3.2.0", "3.2.1"] {
                        let reference = try Data(contentsOf: references.appendingPathComponent("\(stem)-\(version).pnm"))
                        try require(reference.count == pnm.count && reference.starts(with: header), "Oracle layout differs")
                        let differences = zip(samples, reference.dropFirst(header.count)).map { abs(Int($0) - Int($1)) }
                        let maximum = differences.max() ?? 0
                        // Established on 12 October in JPEGDecodeParityTests,
                        // independently of the stricter November timing gate.
                        try require(maximum <= 3, "Subsampled RGB channel error exceeds established bound 3")
                        var record: [String: Any] = ["fixture": stem, "requestedBackend": backend,
                            "reportedBackend": String(describing: result.report.backend),
                            "storage": borrowed ? "padded-caller" : "allocated", "oracleVersion": version,
                            "maximumSampleDifference": maximum, "tolerance": 3,
                            "sampleCount": samples.count, "samplesAtMaximumDifference": differences.filter { $0 == maximum }.count,
                            "outputSHA256": digest(pnm), "oracleSHA256": digest(reference),
                            "baselineSHA256": digest(baseline), "matchesBaselineOnSameBackend": true,
                            "matchesOtherStorageLayout": true, "maximumScalarBackendDifference": scalarDifference,
                            "reportedCopyEvents": result.report.copyEvents.count]
                        if borrowed {
                            record["callerAllocationIdentityPreserved"] = true
                            record["prefixAndRowPaddingPreserved"] = true
                            record["reportedPixelAllocationCount"] = result.report.pixelAllocationCount
                        }
                        records.append(record)
                    }
                }
            }
        }
        let result: [String: Any] = ["status": "passed", "decodeCases": 8,
            "oracleComparisons": records.count, "records": records,
            "scope": "8-bit 4:2:0, full-resolution integer output; no performance timings; benchmark tolerance 2 unchanged",
            "copyEvidence": "Public allocation identity and operation reports with exact samples and padding checks; not fresh allocator telemetry"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
