import Foundation
import SwiftJLI
import JPEGComparator

private struct ProbeError: Error { let message: String }

// This owner is local to one task. No C pointer is shared with another task,
// and no compressed-input pointer survives the synchronous C decoder call.
private final class TurboImage {
    private(set) var value = jpeg_bench_image()
    init(_ data: Data) throws {
        try withUnsafeTemporaryAllocation(of: CChar.self, capacity: 512) { error in
            error.initialize(repeating: 0)
            let status = data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
                jpeg_bench_decode(input.baseAddress?.assumingMemoryBound(to: UInt8.self), input.count,
                                  &value, error.baseAddress, error.count)
            }
            guard status == 0, value.pixels != nil, value.byte_count > 0 else {
                let text = String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                throw ProbeError(message: "libjpeg comparator: " + text)
            }
        }
    }
    deinit { jpeg_bench_free(&value) }
    func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try withExtendedLifetime(self) {
            try body(UnsafeRawBufferPointer(start: value.pixels, count: Int(value.byte_count)))
        }
    }
}

private func hash(_ bytes: UnsafeRawBufferPointer) -> String {
    // Full-output FNV-1a identity aid; the quality gate compares every sample,
    // rather than relying on a non-cryptographic checksum. No hash output copy.
    var value: UInt64 = 14695981039346656037
    for byte in bytes { value = (value ^ UInt64(byte)) &* 1099511628211 }
    return String(value, radix: 16)
}

private func seconds(_ start: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
}

private func stats(_ samples: [Double]) -> [String: Any] {
    let sorted = samples.sorted()
    return ["samplesSeconds": samples, "medianSeconds": (sorted[9] + sorted[10]) / 2,
            "p95Seconds": sorted[18], "minimumSeconds": sorted[0], "maximumSeconds": sorted[19]]
}

private func emit(_ object: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self))
}

@main struct Compare {
    static func main() async throws { try await run() }
    @concurrent private static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 6, let workers = Int(args[3]), workers > 0,
              let tolerance = Int(args[4]), [0, 2, 4].contains(tolerance),
              let round = Int(args[5]), round > 0 else {
            throw ProbeError(message: "Usage: Compare timing|memory-swift|memory-turbo|errors fixture workers tolerance round")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let decoder = try SwiftJLI.Decoder()
        let limits = try ResourceLimits(maximumWorkspaceBytes: 8 * 1024 * 1024 * 1024,
            maximumWorkers: workers, maximumMemoryBytes: 10 * 1024 * 1024 * 1024)
        let options = DecodeOptions(resourceLimits: limits)
        var row: [String: Any] = ["fixture": URL(fileURLWithPath: args[2]).lastPathComponent,
                                 "workerCeiling": workers, "round": round, "tolerance": tolerance,
                                 "inputBytes": data.count]
        if args[1] == "memory-swift" {
            let decoded = try await decoder.decode(data, options: options)
            row["engine"] = "SwiftJLI"
            row["outputBytes"] = decoded.image.storage.byteCount
            row["outputFNV1a64"] = try decoded.image.storage.withUnsafeBytes { hash($0) }
            try withExtendedLifetime((data, decoded)) { try emit(row) }
            return
        }
        if args[1] == "memory-turbo" {
            let decoded = try TurboImage(data)
            row["engine"] = "libjpeg-turbo"
            row["outputBytes"] = decoded.value.byte_count
            row["outputFNV1a64"] = decoded.withBytes { hash($0) }
            try withExtendedLifetime((data, decoded)) { try emit(row) }
            return
        }
        if args[1] == "errors" {
            for corrupt in [Data(), Data([0xFF, 0xD8, 0xFF]), Data(data.prefix(max(1, data.count / 2))),
                            Data(data.dropLast(min(2, data.count)))] {
                do {
                    _ = try TurboImage(corrupt)
                    throw ProbeError(message: "Malformed input unexpectedly accepted")
                } catch let error as ProbeError {
                    guard error.message.hasPrefix("libjpeg comparator:") else { throw error }
                }
            }
            row["containedCErrors"] = 4
            try emit(row)
            return
        }
        guard args[1] == "timing" else { throw ProbeError(message: "Unknown mode") }

        // Both complete outputs exist only for this separate pre-timing quality
        // gate. Neither is retained during any measured decode iteration.
        do {
            let swift = try await decoder.decode(data, options: options)
            let turbo = try TurboImage(data)
            let d = swift.image.descriptor
            guard case .unsignedInteger = d.sampleType,
                  d.width == Int(turbo.value.width), d.height == Int(turbo.value.height),
                  d.components.count == Int(turbo.value.components),
                  d.meaningfulBits == Int(turbo.value.precision), d.storageBits == Int(turbo.value.storage_bits),
                  d.planes.count == 1, let plane = d.planes.first,
                  plane.offset == 0, plane.rowBytes == Int(turbo.value.row_bytes),
                  plane.sampleStride == d.storageBits / 8,
                  plane.pixelStride == d.components.count * d.storageBits / 8,
                  swift.image.storage.byteCount == Int(turbo.value.byte_count) else {
                throw ProbeError(message: "Output precision/colour/layout mismatch")
            }
            if d.components.count == 1 {
                guard d.colour == .greyscale else { throw ProbeError(message: "Expected greyscale") }
            } else {
                guard d.colour == .rgb, d.components == [.red, .green, .blue] else { throw ProbeError(message: "Expected RGB") }
            }
            let maximum = try swift.image.storage.withUnsafeBytes { sw in
                turbo.withBytes { c in
                    var maximum = 0
                    if d.storageBits == 8 {
                        for i in 0..<sw.count { maximum = max(maximum, abs(Int(sw[i]) - Int(c[i]))) }
                    } else {
                        for i in stride(from: 0, to: sw.count, by: 2) {
                            let raw = sw.loadUnaligned(fromByteOffset: i, as: UInt16.self)
                            let sample = d.byteOrder == .littleEndian ? UInt16(littleEndian: raw) : UInt16(bigEndian: raw)
                            maximum = max(maximum, abs(Int(sample) - Int(c.loadUnaligned(fromByteOffset: i, as: UInt16.self))))
                        }
                    }
                    return maximum
                }
            }
            row["maximumSampleDifference"] = maximum
            row["outputBytes"] = swift.image.storage.byteCount
            row["storageBits"] = d.storageBits
            row["meaningfulBits"] = d.meaningfulBits
            row["components"] = d.components.count
            row["swiftFNV1a64"] = try swift.image.storage.withUnsafeBytes { hash($0) }
            row["turboFNV1a64"] = turbo.withBytes { hash($0) }
            guard maximum <= tolerance else {
                row["status"] = "quality-excluded"
                try emit(row)
                return
            }
        }
        var swiftSamples: [Double] = [], turboSamples: [Double] = []
        var swiftCheck: UInt64 = 0, turboCheck: UInt64 = 0
        for iteration in 0..<25 {
            let order = (iteration + round).isMultiple(of: 2) ? ["turbo", "swift"] : ["swift", "turbo"]
            for engine in order {
                if engine == "swift" {
                    let started = ContinuousClock.now
                    let output = try await decoder.decode(data, options: options)
                    let elapsed = seconds(started)
                    if iteration >= 5 { swiftSamples.append(elapsed) }
                    swiftCheck &+= try output.image.storage.withUnsafeBytes {
                        UInt64($0[0]) + UInt64($0[$0.count - 1])
                    }
                    withExtendedLifetime(output) {}
                } else {
                    let started = ContinuousClock.now
                    let output = try TurboImage(data)
                    let elapsed = seconds(started)
                    if iteration >= 5 { turboSamples.append(elapsed) }
                    turboCheck &+= output.withBytes { UInt64($0[0]) + UInt64($0[$0.count - 1]) }
                    withExtendedLifetime(output) {}
                }
                // Both output owners leave scope before the next engine runs;
                // output destruction/free is outside the measured interval.
            }
        }
        row["status"] = "passed"
        row["swift"] = stats(swiftSamples)
        row["turbo"] = stats(turboSamples)
        row["swiftEdgeCheck"] = swiftCheck
        row["turboEdgeCheck"] = turboCheck
        row["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        try emit(row)
    }
}
