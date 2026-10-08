// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin
import SwiftJLI

struct Measurement {
    let before: malloc_statistics_t
    let after: malloc_statistics_t
    var liveIncrease: Int { max(0, Int(after.size_in_use) - Int(before.size_in_use)) }
}
@MainActor var startingStats = malloc_statistics_t()
func currentStats() -> malloc_statistics_t {
    var result = malloc_statistics_t()
    malloc_zone_statistics(nil, &result)
    return result
}
@MainActor func beginMeasuredScope() { startingStats = currentStats() }
@MainActor func endMeasuredScope() -> Measurement { Measurement(before: startingStats, after: currentStats()) }
func snapshot(_ m: Measurement) throws -> [String: Any] {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CodecError(.internalFailure, "getrusage failed") }
    return ["allZonesBytesInUseBefore": m.before.size_in_use, "allZonesBytesInUseAfter": m.after.size_in_use,
        "liveIncreaseBytes": m.liveIncrease, "allZonesHighWaterBytes": m.after.max_size_in_use,
        "processPeakRSSBytes": usage.ru_maxrss, "blocksInUseBefore": m.before.blocks_in_use,
        "blocksInUseAfter": m.after.blocks_in_use]
}
@MainActor func calibrate() throws -> Bool {
    let before = currentStats()
    let storage = try OwnedImageStorage(byteCount: 4 * 1024 * 1024)
    let after = withExtendedLifetime(storage) { currentStats() }
    return after.size_in_use >= before.size_in_use + storage.byteCount
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CodecError(.internalFailure, message) }
}
func emit(_ value: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
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


@main struct AppleMemoryProbe {
    static func main() async {
        do { try await runMemoryStress(controlCopy: CommandLine.arguments.contains("--control-copy")) }
        catch { FileHandle.standardError.write(Data("Apple memory probe failed: \(error)\n".utf8)); exit(1) }
    }
}
