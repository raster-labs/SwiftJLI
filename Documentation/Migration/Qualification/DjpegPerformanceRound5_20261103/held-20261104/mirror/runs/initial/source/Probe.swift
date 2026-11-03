// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit
import Darwin
@testable import SwiftJLI

struct ProbeDataset {
    let name: String
    let precision: Int
    let quantiser: [Float]
    var coefficients: [Int32]
    let timingEligible: Bool
}

struct DatasetReceipt: Codable {
    let name: String
    let precision: Int
    let blocks: Int
    let inputSHA256: String
    let quantiserSHA256: String
    let outputSHA256: String
    let exactFloatSamplesCompared: Int
    let counts: MirrorCounts
}

func digest<T>(_ values: [T]) -> String {
    values.withUnsafeBufferPointer { buffer in
        SHA256.hash(data: Data(UnsafeRawBufferPointer(buffer))).map { String(format: "%02x", $0) }.joined()
    }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw MirrorFailure.invalid(message) }
}

/// Only the frozen module executes this reference. Every raw pointer remains
/// inside its owning array borrow; Float results are copied before it returns.
func frozenReference(_ dataset: ProbeDataset) throws -> [Float] {
    var result: [Float] = []
    for first in stride(from: 0, to: dataset.coefficients.count, by: 8192*64) {
        let end = min(dataset.coefficients.count, first+8192*64)
        var coefficients = Array(dataset.coefficients[first..<end])
        let values = try NativeOperation.$current.withValue(.init(seconds: 120,
            backend: .accelerated, maximumWorkers: 1)) {
            try coefficients.withUnsafeMutableBufferPointer { buffer in
                try dataset.quantiser.withUnsafeBufferPointer { quantiser in
                    try BlockLocalIDCT.reconstruct(buffer, quantiser: quantiser, precision: dataset.precision)
                }
                guard let base = buffer.baseAddress else { throw MirrorFailure.invalid("Empty reference buffer") }
                return base.withMemoryRebound(to: Float.self, capacity: buffer.count) { values in
                    Array(UnsafeBufferPointer(start: values, count: buffer.count))
                }
            }
        }
        result.append(contentsOf: values)
    }
    return result
}

func syntheticDatasets(_ kernel: CertifiedMirror) -> [ProbeDataset] {
    var datasets: [ProbeDataset] = []
    for precision in [8, 12] {
        let limit = Int32(1 << (precision+2))
        let quantisers: [(String, [Float])] = [
            ("ones", Array(repeating: 1, count: 64)),
            ("maximum", Array(repeating: 65535, count: 64)),
            ("alternating", (0..<64).map { $0 & 1 == 0 ? 1 : 65535 }),
            ("ramp", (0..<64).map { Float(1+$0*997) })
        ]
        for (name, quantiser) in quantisers {
            var blocks: [Int32] = []
            blocks += Array(repeating: 0, count: 64)
            let magnitudes: [Int32] = [1,-1,4,-4,limit-1,1-limit,limit,-limit]
            for frequency in 0..<64 {
                for magnitude in magnitudes {
                    var block = [Int32](repeating: 0, count: 64)
                    block[kernel.inverseZigzag[frequency]] = magnitude
                    blocks += block
                }
            }
            for sign in [Int32(-1),Int32(1)] {
                blocks += (0..<64).map { $0 & 1 == 0 ? sign*limit : -sign*limit }
                blocks += Array(repeating: sign*limit, count: 64)
            }
            // Outside public coefficient bounds, but finite: tests reference
            // fallback/domain handling without changing the admitted product.
            for extreme in [Int32.min, Int32.max] {
                blocks += Array(repeating: extreme, count: 64)
                var block = [Int32](repeating: 0, count: 64)
                block[0] = extreme; blocks += block
            }
            datasets.append(.init(name: "adversarial-\(precision)-\(name)", precision: precision,
                quantiser: quantiser, coefficients: blocks, timingEligible: false))
        }
        var seed: UInt64 = 0x53574946544A4C49 ^ UInt64(precision)
        var dense: [Int32] = []
        let amplitude = precision == 8 ? 128 : 2048
        for _ in 0..<(512*64) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            dense.append(Int32(Int((seed >> 32) % UInt64(amplitude*2+1))-amplitude))
        }
        datasets.append(.init(name: "synthetic-dense-\(precision)", precision: precision,
            quantiser: Array(repeating: 1, count: 64), coefficients: dense, timingEligible: true))
    }
    return datasets
}

/// Read-only fixture extraction, performed only when this executable is run.
/// Entropy coefficients are copied synchronously from the original module's
/// bounded consumer. No borrowed pointer is stored or used asynchronously.
func fixtureDataset(_ path: String) throws -> ProbeDataset {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    try require(data.count <= 64*1024*1024, "Standalone fixture input cap")
    let limits = try ResourceLimits(maximumWorkspaceBytes: 8*1024*1024*1024,
        maximumWorkers: 1, maximumMemoryBytes: 10*1024*1024*1024)
    return try NativeOperation.$current.withValue(.init(seconds: 120, backend: .scalarCPU, maximumWorkers: 1)) {
        let parsed = try JPEGCodec.parse(data, options: .init(resourceLimits: limits))
        let frame = parsed.frameInfo
        try require(!frame.isLossless && !frame.isProgressive && frame.components.count == 1
            && parsed.scans.count == 1 && (frame.precision == 8 || frame.precision == 12), "Fixture must be sequential8/12 greyscale")
        let component = frame.components[0], scan = parsed.scans[0]
        try require(component.horizontalSampling == 1 && component.verticalSampling == 1, "Fixture sampling")
        let columns = (frame.width+7)/8, rows = (frame.height+7)/8
        let blocks = try checkedMultiply(columns, rows)
        try require(blocks <= 262144, "Standalone fixture coefficient cap")
        let selector = scan.header.components.first { $0.componentSelector == component.id }
        let dcID = selector?.dcTableId ?? 0, acID = selector?.acTableId ?? 0
        let dc = scan.dcTables[dcID] ?? (dcID == 1 ? StandardHuffmanTables.dcChrominance : StandardHuffmanTables.dcLuminance)
        let ac = scan.acTables[acID] ?? (acID == 1 ? StandardHuffmanTables.acChrominance : StandardHuffmanTables.acLuminance)
        let lookup = ACLookahead(table: ac, blockCount: blocks)
        var reader = BitReader(data: scan.entropyData)
        var coefficients: [Int32] = []
        coefficients.reserveCapacity(try checkedMultiply(blocks,64))
        try SequentialGreyscaleDecoder.decodeBatches(reader: &reader, dcTable: dc, acTable: ac,
            lookup: lookup, blocksPerRow: columns, blockRows: rows, precision: frame.precision,
            restartInterval: parsed.restartInterval) { buffer, first in
                try require(first*64 == coefficients.count, "Non-contiguous fixture coefficient batch")
                coefficients.append(contentsOf: buffer)
            }
        var quantiser = [Float](repeating: 0, count: 64)
        let zigzagQuantiser = parsed.quantTables[component.quantTableIndex]
        for index in 0..<64 { quantiser[Quantization.zigzagOrder[index]] = Float(zigzagQuantiser[index]) }
        return ProbeDataset(name: "fixture-"+URL(fileURLWithPath: path).lastPathComponent,
            precision: frame.precision, quantiser: quantiser, coefficients: coefficients, timingEligible: true)
    }
}

func verifyDataset(_ dataset: ProbeDataset, kernel: CertifiedMirror) throws -> DatasetReceipt {
    let reference = try frozenReference(dataset)
    let expected = try reference.map { try CertifiedMirror.integerFromCentred($0) }
    let exact = try kernel.transform(dataset.coefficients, quantiser: dataset.quantiser,
        precision: dataset.precision, certified: false).0
    try require(exact == expected, "Source exact integer graph differs from frozen reference: \(dataset.name)")
    var first = [SIMD8<Float>](repeating: SIMD8(repeating: 0), count: 8)
    for block in 0..<(dataset.coefficients.count/64) {
        kernel.firstPass(dataset.coefficients, offset: block*64, quantiser: dataset.quantiser, into: &first)
        for row in 0..<8 {
            let values = kernel.exactSecond(first[row])
            for lane in 0..<8 {
                let value = CertifiedMirror.centredClipped(values[lane], precision: dataset.precision)
                try require(value.bitPattern == reference[block*64+row*8+lane].bitPattern,
                    "Source exact Float graph differs from frozen reference: \(dataset.name), block\(block)")
            }
        }
    }
    let (candidate, counts) = try kernel.transform(dataset.coefficients, quantiser: dataset.quantiser,
        precision: dataset.precision, certified: true, audit: true)
    try require(candidate == expected, "Certified integer mismatch: \(dataset.name)")
    try require(counts.certifiedPixels+counts.ambiguousPixels+counts.domainFallbackPixels == candidate.count,
        "Incomplete candidate accounting")
    return .init(name: dataset.name, precision: dataset.precision, blocks: dataset.coefficients.count/64,
        inputSHA256: digest(dataset.coefficients), quantiserSHA256: digest(dataset.quantiser),
        outputSHA256: digest(candidate), exactFloatSamplesCompared: reference.count, counts: counts)
}

struct BoundaryReceipt: Codable {
    var testedRows = 0
    var testedHalfThresholds = 0
    var testedInvalidCertificates = 0
    var domainRows = 0
    var counts = MirrorCounts()
}

func boundaryTests(_ kernel: CertifiedMirror) throws -> BoundaryReceipt {
    var result = BoundaryReceipt()
    for precision in [8,12] {
        let maximum = (1 << precision)-1, centre = Float(1 << (precision-1))
        for dc in [Float(0),Float(1),Float(100000),Float(-100000)] {
            var row = SIMD8<Float>(repeating: 0); row[0] = dc
            var output = [UInt16](repeating: 0, count: 8), counts = MirrorCounts()
            try kernel.certifiedRow(row, precision: precision, audit: true,
                output: &output, offset: 0, counts: &counts)
            let exact = kernel.exactSecond(row)
            for lane in 0..<8 {
                try require(output[lane] == CertifiedMirror.integerFromCentred(CertifiedMirror.centredClipped(exact[lane], precision: precision)),
                    "Interior/clipped row mismatch")
            }
            result.testedRows += 1; result.counts.add(counts)
        }
        for threshold in 0..<maximum {
            result.testedHalfThresholds += 1
            // Row-level cases, not claims that these are encoded JPEG blocks.
            // Position0's real dot lies at/near each integer half-threshold.
            let target = Double(threshold)+0.5-Double(centre)
            let middle = Float(target/Double(kernel.matrix[0][0]))
            let values = [middle.nextDown.nextDown,middle.nextDown,middle,middle.nextUp,middle.nextUp.nextUp]
            for value in values {
                var row = SIMD8<Float>(repeating: 0); row[0] = value
                let expected = kernel.exactSecond(row)
                var output = [UInt16](repeating: 0, count: 8), counts = MirrorCounts()
                try kernel.certifiedRow(row, precision: precision, audit: true,
                    output: &output, offset: 0, counts: &counts)
                for lane in 0..<8 {
                    try require(kernel.exactPixel(row, position: lane).bitPattern == expected[lane].bitPattern,
                        "Scalar fallback FMA graph differs from SIMD reference")
                    let integer = try CertifiedMirror.integerFromCentred(CertifiedMirror.centredClipped(expected[lane], precision: precision))
                    try require(output[lane] == integer, "Half-threshold mismatch")
                }
                result.testedRows += 1; result.counts.add(counts)
            }
        }
        for sample in [-Float.infinity, Float.infinity, Float.nan] {
            try require(CertifiedMirror.certificate(sample, radius: 0, precision: precision) == nil,
                "Nonfinite sample was certified")
            result.testedInvalidCertificates += 1
        }
        for radius in [-1.0, Double.infinity, Double.nan] {
            try require(CertifiedMirror.certificate(0, radius: radius, precision: precision) == nil,
                "Invalid radius was certified")
            result.testedInvalidCertificates += 1
        }
        // Force false/nonfinite-domain fallback, preserving reference outcome.
        for value in [Float.leastNonzeroMagnitude, Float.leastNormalMagnitude, Float(1e20), Float.infinity, -Float.infinity, Float.nan] {
            var row = SIMD8<Float>(repeating: 0); row[0] = value
            try require(kernel.radius(row) == nil, "Expected explicit invalid-domain fallback")
            let expected = kernel.exactSecond(row)
            var output = [UInt16](repeating: 0, count: 8), counts = MirrorCounts()
            let expectedThrows = expected.contains { !CertifiedMirror.centredClipped($0, precision: precision).isFinite }
            do {
                try kernel.certifiedRow(row, precision: precision, audit: true,
                    output: &output, offset: 0, counts: &counts)
                try require(!expectedThrows, "Nonfinite reference unexpectedly succeeded")
                for lane in 0..<8 {
                    try require(output[lane] == CertifiedMirror.integerFromCentred(CertifiedMirror.centredClipped(expected[lane], precision: precision)),
                        "Domain fallback changed clipped integer")
                }
            } catch let failure as MirrorFailure {
                guard expectedThrows,
                      failure.description == "Non-finite or out-of-range reconstructed sample" else { throw failure }
            }
            try require(counts.domainFallbackPixels == 8, "Missing domain fallback accounting")
            result.domainRows += 1
        }
    }
    try require(result.counts.ambiguousPixels > 0 && result.counts.certifiedPixels > 0,
        "Boundary corpus did not exercise both certificate outcomes")
    return result
}

struct TimingReceipt: Codable {
    let name: String
    let blocks: Int
    let exactSeconds: [Double]
    let certifiedSeconds: [Double]
    let counts: MirrorCounts
    let outputSHA256: String
}

func timings(_ dataset: ProbeDataset, kernel: CertifiedMirror) throws -> TimingReceipt {
    let expected = try kernel.transform(dataset.coefficients, quantiser: dataset.quantiser,
        precision: dataset.precision, certified: false).0
    var exactTimes: [Double] = [], candidateTimes: [Double] = []
    var candidateCounts = MirrorCounts()
    for round in 0..<25 {
        for certified in (round & 1 == 0 ? [false,true] : [true,false]) {
            let start = ContinuousClock.now
            let (output, counts) = try kernel.transform(dataset.coefficients, quantiser: dataset.quantiser,
                precision: dataset.precision, certified: certified)
            let elapsed = start.duration(to: .now).components
            let seconds = Double(elapsed.seconds)+Double(elapsed.attoseconds)/1e18
            // Full equality, hashing and record work occur after the timer.
            try require(output == expected, "Timed output mismatch")
            if round >= 5 {
                if certified { candidateTimes.append(seconds) } else { exactTimes.append(seconds) }
            }
            if certified { candidateCounts = counts }
        }
    }
    return .init(name: dataset.name, blocks: dataset.coefficients.count/64,
        exactSeconds: exactTimes, certifiedSeconds: candidateTimes,
        counts: candidateCounts, outputSHA256: digest(expected))
}

@main struct MirrorProbe {
    static func main() throws {
        var mode = "correctness", fixturePaths: [String] = []
        var index = 1
        while index < CommandLine.arguments.count {
            let flag = CommandLine.arguments[index]; index += 1
            guard index < CommandLine.arguments.count else { throw MirrorFailure.invalid("Missing argument") }
            let value = CommandLine.arguments[index]; index += 1
            if flag == "--mode" { mode = value }
            else if flag == "--fixture" { fixturePaths.append(value) }
            else { throw MirrorFailure.invalid("Unknown argument") }
        }
        try require(mode == "correctness" || mode == "timing", "Unknown mode")
        try require(BlockLocalIDCT.available, "Frozen ARM64 FMA reference unavailable")
        let kernel = try CertifiedMirror()
        try require(kernel.basisDomainValid, "Actual Float basis outside certificate domain")
        var datasets = syntheticDatasets(kernel)
        for path in fixturePaths { datasets.append(try fixtureDataset(path)) }
        var result: [String: Any] = ["mode":mode,
            "referenceRevision":"ba2771eb3393c703fba106082720d9987c0594e9",
            "referenceStatus":"Unaccepted FMA composition; standalone numerical reference only",
            "basisFloatBits":kernel.basisBits,"mirrorFloatBits":kernel.mirrorBits,
            "maximumMirrorResidual":kernel.maximumMirrorResidual,"upwardWeights":kernel.weights,
            "positiveSumInflation":kernel.positiveSumInflation,
            "sampleScope":"All64 samples per coefficient block, including padded edge positions; not cropped image-only fallback rates",
            "scope":"Integer second-pass prototype only; Float32 route not prototyped or changed"]
        let encoder = JSONEncoder()
        if mode == "correctness" {
            let records = try datasets.map { try verifyDataset($0, kernel: kernel) }
            let boundaries = try boundaryTests(kernel)
            result["datasets"] = try JSONSerialization.jsonObject(with: encoder.encode(records))
            result["boundaries"] = try JSONSerialization.jsonObject(with: encoder.encode(boundaries))
            result["status"] = "all integer, interval and exact-source Float-reference checks passed"
        } else {
            let records = try datasets.filter(\.timingEligible).map { try timings($0, kernel: kernel) }
            result["timings"] = try JSONSerialization.jsonObject(with: encoder.encode(records))
            result["method"] = "Same binary, common owning buffers/exact first pass; interleaved arms,5warmups20samples; output allocation and certificate accounting included; full comparison outside timer. Not full decoder, CLI, RSS or frozen-in-place API latency."
            result["status"] = "standalone transform timings only; shared-host provisional"
        }
        try require(fegetround() == FE_TONEAREST, "Rounding mode changed")
        let output = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data([10]))
    }
}
