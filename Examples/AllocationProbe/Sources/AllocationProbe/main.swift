// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
import HeapProbe
import Glibc

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CodecError(.internalFailure, message) }
}
func emit(_ value: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
}
func snapshot(_ stats: HPStats) throws -> [String: Any] {
    try require(stats.overflow == 0, "Allocator table overflow invalidates measurement")
    let sizes = (0..<hp_bucket_count()).map { hp_bucket($0) }.sorted { $0.size < $1.size }
        .map { ["requestedBytes": $0.size, "count": $0.count] }
    return ["allocations": stats.allocations, "frees": stats.frees,
        "totalRequestedBytes": stats.requested_bytes, "liveRequestedBytes": stats.live_bytes,
        "peakRequestedBytes": stats.peak_bytes, "liveBlocks": stats.live_blocks,
        "peakBlocks": stats.peak_blocks, "overflow": stats.overflow, "allocationSizes": sizes]
}
func padded(_ d: ImageDescriptor) throws -> ImageDescriptor {
    let row = d.width * d.components.count * (d.storageBits / 8) + 64
    let p = try PlaneDescriptor(width: d.width, height: d.height, components: Array(d.components.indices),
        sampleStride: d.storageBits / 8, pixelStride: d.components.count * (d.storageBits / 8),
        rowBytes: row, byteCount: row * d.height)
    return try ImageDescriptor(width: d.width, height: d.height, sampleType: d.sampleType,
        storageBits: d.storageBits, meaningfulBits: d.meaningfulBits, components: d.components,
        colour: d.colour, planes: [p], iccProfile: d.iccProfile)
}
func equalSamples(_ a: Image, _ b: Image) throws {
    let da = a.descriptor, db = b.descriptor
    try require(da.width == db.width && da.height == db.height && da.storageBits == db.storageBits &&
        da.meaningfulBits == db.meaningfulBits && da.sampleType == db.sampleType &&
        da.components == db.components && da.iccProfile == db.iccProfile, "Interpretation changed")
    let row = da.width * da.components.count * (da.storageBits / 8)
    try a.storage.withUnsafeBytes { aa in try b.storage.withUnsafeBytes { bb in
        for y in 0..<da.height {
            for x in 0..<row {
                try require(aa[y * da.planes[0].rowBytes + x] == bb[y * db.planes[0].rowBytes + x], "Sample mismatch")
            }
            for x in row..<db.planes[0].rowBytes {
                try require(bb[y * db.planes[0].rowBytes + x] == 0, "Destination padding overwritten")
            }
        }
    } }
}

@main struct AllocationProbe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Allocation probe failed: \(error)\n".utf8))
            exit(1)
        }
    }
    static func run() async throws {
        let controlCopy = CommandLine.arguments.dropFirst().contains("--control-copy")
        let measureEncode = CommandLine.arguments.dropFirst().contains("--encode")
        try require(hp_calibrate() == 1, "glibc malloc/calloc/realloc/posix_memalign calibration failed")
        // Check that Swift heap allocations actually traverse the interposer too.
        hp_begin()
        let storage = try OwnedImageStorage(byteCount: 1_048_576)
        let calibration = hp_end()
        try require(calibration.peak_bytes >= 1_048_576 && calibration.live_bytes >= 1_048_576,
            "Swift storage allocation was not observed")
        try emit(["event": "calibration", "cPassed": true, "swiftByteCount": storage.byteCount,
            "measurement": snapshot(calibration)])
        for size in [257, 1024] {
            let profiles = measureEncode ? ["lossless16", "dct12", "rgb8", "progressiveRGB8", "xyb8"]
                : ["lossless16", "dct12", "rgb8", "xyb8", "xybFloat32"]
            for profile in profiles {
                let bits = profile == "lossless16" ? 16 : profile == "dct12" ? 12 : 8
                let nc = profile == "lossless16" || profile == "dct12" ? 1 : 3
                let bps = bits > 8 ? 2 : 1, row = size * nc * bps
                let plane = try PlaneDescriptor(width: size, height: size, components: Array(0..<nc),
                    sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: row * size)
                let descriptor = try ImageDescriptor(width: size, height: size, storageBits: bps * 8,
                    meaningfulBits: bits, components: nc == 1 ? [.grey] : [.red, .green, .blue],
                    colour: nc == 1 ? .greyscale : .rgb, planes: [plane])
                let source = try ImageDestination.allocate(descriptor: descriptor).write { raw in
                    for y in 0..<size { for x in 0..<(size * nc) {
                        let sample = (x * 17 + y * 31 + x * y % 257) & ((1 << bits) - 1)
                        raw[y * row + x * bps] = UInt8(truncatingIfNeeded: sample)
                        if bps == 2 { raw[y * row + x * bps + 1] = UInt8(sample >> 8) }
                    } }
                }
                let xyb = profile.hasPrefix("xyb")
                let encoder = try Encoder(configuration: .init(mode: bits == 16 ? .lossless : .lossy,
                    codecOptions: .init(dct: .init(chromaSubsampling: xyb ? .yuv444 : .yuv420,
                        progressiveMode: profile == "progressiveRGB8" ? .spectralSelection : .sequential,
                        colourSpace: xyb ? .xybFromSRGB : .yCbCr))))
                let limits = try ResourceLimits(maximumWorkspaceBytes: 1024 * 1024 * 1024)
                let jpeg = try await encoder.encode(source, options: .init(resourceLimits: limits))
                if measureEncode {
                    for _ in 0..<3 { _ = try await encoder.encode(source, options: .init(resourceLimits: limits)) }
                    for repetition in 0..<3 {
                        hp_begin()
                        let encoded: EncodedImage
                        do { encoded = try await encoder.encode(source, options: .init(resourceLimits: limits)) }
                        catch { _ = hp_end(); throw error }
                        // Positive control: a full source copy must add a measured
                        // source-sized allocation even when the codec report is unchanged.
                        let copy = controlCopy ? try source.storage.withUnsafeBytes { Array($0) } : nil
                        let stats = withExtendedLifetime(copy) { hp_end() }
                        let measurement = try snapshot(stats)
                        try require(encoded.data == jpeg.data, "Encoder output changed")
                        try require(encoded.report.pixelAllocationCount == 0, "Encoder pixel report changed")
                        try emit(["event": "encode", "profile": profile, "width": size, "height": size,
                            "entry": "borrowedSource", "repetition": repetition,
                            "logicalPixelBytes": source.storage.byteCount, "sourceCapacity": source.storage.byteCount,
                            "controlCopy": controlCopy, "compressedBytes": encoded.data.count,
                            "codestreamsMatch": true, "measurement": measurement])
                    }
                    continue
                }
                let decoder = try Decoder(configuration: .init(sampleFormat:
                    profile == "xybFloat32" ? .float32NormalisedSRGB : .nativeInteger))
                let reference = try await decoder.decode(jpeg.data)
                let output = try padded(reference.image.descriptor)
                // Warm both entry paths before measuring; pre-existing heap is excluded.
                for _ in 0..<3 {
                    _ = try await decoder.decode(jpeg.data)
                    _ = try await decoder.decode(jpeg.data, into: ImageDestination.allocate(descriptor: output))
                }
                for repetition in 0..<3 {
                    for callerOwned in repetition % 2 == 0 ? [false, true] : [true, false] {
                        let destination = callerOwned ? try ImageDestination.allocate(descriptor: output) : nil
                        hp_begin()
                        let decoded: DecodedImage
                        do {
                            if let destination { decoded = try await decoder.decode(jpeg.data, into: destination) }
                            else { decoded = try await decoder.decode(jpeg.data) }
                        } catch { _ = hp_end(); throw error }
                        // Positive control: an extra frame copy must be visible even
                        // though the decoder's reported allocation identity is unchanged.
                        let copy = controlCopy ? try decoded.image.storage.withUnsafeBytes { Array($0) } : nil
                        let stats = withExtendedLifetime(copy) { hp_end() }
                        let measurement = try snapshot(stats)
                        try equalSamples(reference.image, decoded.image)
                        if let destination {
                            try require(decoded.image.storage.allocationID == destination.storage.allocationID,
                                "Caller allocation identity changed")
                        }
                        try require(decoded.report.pixelAllocationCount == (callerOwned ? 0 : 1), "Report count changed")
                        try emit(["event": "decode", "profile": profile, "width": size, "height": size,
                            "entry": callerOwned ? "callerDestination" : "allocating", "repetition": repetition,
                            "logicalPixelBytes": reference.image.storage.byteCount,
                            "destinationCapacity": decoded.image.storage.byteCount,
                            "controlCopy": controlCopy,
                            "compressedBytes": jpeg.data.count, "samplesMatch": true,
                            "measurement": measurement])
                    }
                }
            }
        }
    }
}
