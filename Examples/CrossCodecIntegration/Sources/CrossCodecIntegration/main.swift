// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
import SwiftJ2K
#if canImport(HeapProbe)
import HeapProbe
#endif

// Each adapter retains the sealed owner, forwards scoped reads and preserves its
// allocation identity. No pointers, arrays or mutable providers cross the adapter.
private struct JPEGReader: SwiftJLI.ReadOnlyImageStorage {
    let owner: any SwiftJ2K.ReadOnlyImageStorage
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeBytes(body)
    }
}
private struct J2KReader: SwiftJ2K.ReadOnlyImageStorage {
    let owner: any SwiftJLI.ReadOnlyImageStorage
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeBytes(body)
    }
}
private struct Failure: Error { let message: String }
private func require(_ ok: Bool, _ message: String) throws {
    if !ok { throw Failure(message: message) }
}
private func sample(_ x: Int, _ y: Int, _ bits: Int) -> UInt16 {
    let max = (1 << bits) - 1
    return UInt16(x == 0 && y == 0 ? 0 : x == 1 && y == 0 ? max : (x * 193 + y * 357 + x * y * 17) & max)
}

private func startHeap() {
    #if canImport(HeapProbe)
    hp_begin()
    #endif
}

private func endHeap(_ direction: String, _ name: String, _ storage: any SwiftJLI.ReadOnlyImageStorage) throws {
    #if canImport(HeapProbe)
    let control = ProcessInfo.processInfo.environment["SWIFTJLI_COPY_CONTROL"] == "1"
    let copy = control ? try storage.withUnsafeBytes { Array($0) } : nil
    let stats = withExtendedLifetime(copy) { hp_end() }
    try require(stats.overflow == 0, "Heap tracker overflow")
    let sizes = (0..<hp_bucket_count()).map { hp_bucket($0) }
        .map { ["requestedBytes": $0.size, "count": $0.count] }
    let data = try JSONSerialization.data(withJSONObject: [
        "event": "heap", "direction": direction, "case": name,
        "destinationCapacity": storage.byteCount, "controlCopy": control,
        "peakRequestedBytes": stats.peak_bytes, "allocations": stats.allocations,
        "liveRequestedBytes": stats.live_bytes, "allocationSizes": sizes
    ], options: .sortedKeys)
    print(String(decoding: data, as: UTF8.self))
    #endif
}

@main struct CrossCodecIntegration {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure(message: "Pass a new evidence directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let jpegEncoder = try SwiftJLI.Encoder(), jpegDecoder = try SwiftJLI.Decoder()
        let j2kEncoder = try SwiftJ2K.Encoder(), j2kDecoder = try SwiftJ2K.Decoder()
        #if canImport(HeapProbe)
        try require(hp_calibrate() == 1, "C heap calibration failed")
        hp_begin()
        let calibrationOwner = try SwiftJLI.OwnedImageStorage(byteCount: 1_048_576)
        let calibration = hp_end()
        try require(calibration.peak_bytes >= 1_048_576, "Swift heap interposition missing")
        let bins = (0..<hp_bucket_count()).map { hp_bucket($0) }.filter { $0.size >= 1_048_576 }
        try require(bins.count == 1, "Ambiguous Swift allocation calibration")
        print("{\"event\":\"calibration\",\"arrayHeaderBytes\":\(Int(bins[0].size) - calibrationOwner.byteCount)}")
        #endif
        for bits in [12, 16] {
            for (width, height) in [(19, 13), (65, 31), (257, 17)] {
                let row = width * 2 + 14
                let name = "\(width)x\(height)-u\(bits)"
                let jd = try SwiftJLI.ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: row)
                let kRow = width * 2 + 22
                let kd = try SwiftJ2K.ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: kRow)
                let kInputDescriptor = try SwiftJ2K.ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: row)
                let jInputDescriptor = try SwiftJLI.ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: kRow)
                let input = try SwiftJLI.ImageDestination.allocate(descriptor: jd).write { bytes in
                    bytes.initializeMemory(as: UInt8.self, repeating: 0xa5)
                    for y in 0..<height { for x in 0..<width {
                        let value = sample(x, y, bits), p = y * row + x * 2
                        bytes[p] = UInt8(truncatingIfNeeded: value); bytes[p + 1] = UInt8(value >> 8)
                    } }
                }
                let originalJPEG = try await jpegEncoder.encode(input)
                let mapped = try SwiftJ2K.Image(descriptor: kInputDescriptor, storage: J2KReader(owner: input.storage))
                let originalJ2K = try await j2kEncoder.encode(mapped)

                // Cancellation at the first processing callback must not publish
                // a result or consume an unwritten destination. The task-local
                // cancellation is isolated from this harness's parent task.
                let cancelledEncode = await Task {
                    do {
                        _ = try await jpegEncoder.encode(input, options: .init(progress: { _ in
                            withUnsafeCurrentTask { $0?.cancel() }
                        }))
                        return false
                    } catch is CancellationError { return true }
                    catch { return false }
                }.value
                try require(cancelledEncode, "Cancelled JPEG encode published a result")
                let reusable = try SwiftJLI.ImageDestination.allocate(descriptor: jd)
                let cancelledDecode = await Task {
                    do {
                        _ = try await jpegDecoder.decode(originalJPEG.data, into: reusable, options: .init(progress: { _ in
                            withUnsafeCurrentTask { $0?.cancel() }
                        }))
                        return false
                    } catch is CancellationError { return true }
                    catch { return false }
                }.value
                try require(cancelledDecode, "Cancelled JPEG decode published a result")
                let retried = try await jpegDecoder.decode(originalJPEG.data, into: reusable)
                try require(retried.image.storage.allocationID == reusable.storage.allocationID,
                            "Pre-write cancellation consumed destination")

                // allowCopy permits supported conversion; it does not invent an
                // endian conversion that SwiftJLI does not implement.
                let incompatible = try SwiftJLI.ImageDescriptor(width: width, height: height,
                    storageBits: 16, meaningfulBits: bits, byteOrder: .bigEndian, planes: jd.planes)
                let wrongEndian = try SwiftJLI.Image(descriptor: incompatible, storage: input.storage)
                for policy in [SwiftJLI.CopyPolicy.requireSharedStorage, .allowCopy] {
                    do {
                        _ = try await jpegEncoder.encode(wrongEndian, options: .init(copyPolicy: policy))
                        throw Failure(message: "Unsupported endian layout encoded")
                    } catch let error as SwiftJLI.CodecError {
                        try require(error.category == .incompatibleImageLayout, "Unexpected endian error")
                    }
                }

                // J2K decode -> sealed owner -> two concurrent JPEG readers.
                startHeap()
                let kOwner = try SwiftJ2K.OwnedImageStorage(byteCount: kd.requiredByteCount)
                let kDestination = try SwiftJ2K.ImageDestination(descriptor: kd, storage: kOwner)
                let fromK = try await j2kDecoder.decode(originalJ2K.data, into: kDestination)
                let toJ = try SwiftJLI.Image(descriptor: jInputDescriptor, storage: JPEGReader(owner: fromK.image.storage))
                try require(toJ.storage.allocationID == kOwner.allocationID, "J2K hand-off changed owner")
                async let j1 = jpegEncoder.encode(toJ)
                async let j2 = jpegEncoder.encode(toJ)
                let (jpeg, secondJPEG) = try await (j1, j2)
                try endHeap("J2K-to-JPEG", name, toJ.storage)
                try require(jpeg.data == secondJPEG.data && jpeg.data == originalJPEG.data, "Concurrent JPEG or hand-off output differs")
                try require(fromK.report.pixelAllocationCount == 0 && fromK.report.copyEvents.isEmpty && jpeg.report.pixelAllocationCount == 0 && jpeg.report.copyEvents.isEmpty, "J2K to JPEG copy report")
                do { _ = try kOwner.reserveWrite(); throw Failure(message: "Sealed J2K owner admitted mutation") }
                catch is SwiftJ2K.CodecError { }

                // JPEG decode -> sealed owner -> two concurrent J2K readers.
                startHeap()
                let jOwner = try SwiftJLI.OwnedImageStorage(byteCount: jd.requiredByteCount)
                let jDestination = try SwiftJLI.ImageDestination(descriptor: jd, storage: jOwner)
                let fromJ = try await jpegDecoder.decode(originalJPEG.data, into: jDestination)
                let toK = try SwiftJ2K.Image(descriptor: kInputDescriptor, storage: J2KReader(owner: fromJ.image.storage))
                try require(toK.storage.allocationID == jOwner.allocationID, "JPEG hand-off changed owner")
                async let k1 = j2kEncoder.encode(toK)
                async let k2 = j2kEncoder.encode(toK)
                let (j2k, secondJ2K) = try await (k1, k2)
                try endHeap("JPEG-to-J2K", name, fromJ.image.storage)
                try require(j2k.data == secondJ2K.data && j2k.data == originalJ2K.data, "Concurrent J2K or hand-off output differs")
                try require(fromJ.report.pixelAllocationCount == 0 && fromJ.report.copyEvents.isEmpty && j2k.report.pixelAllocationCount == 0 && j2k.report.copyEvents.isEmpty, "JPEG to J2K copy report")
                do { _ = try jOwner.reserveWrite(); throw Failure(message: "Sealed JPEG owner admitted mutation") }
                catch is SwiftJLI.CodecError { }
                for y in 0..<height { for x in 0..<width {
                    let expected = sample(x, y, bits)
                    try require(try fromJ.image.sampleUInt16(x: x, y: y) == expected, "JPEG samples differ")
                    try require(try fromK.image.sampleUInt16(x: x, y: y) == expected, "J2K samples differ")
                } }
                // Both allocated destinations start with zero padding. Source input
                // uses 0xa5; equal codestreams above prove padding independence.
                try fromJ.image.storage.withUnsafeBytes { bytes in
                    for y in 0..<height { for p in width * 2..<row where y * row + p < bytes.count {
                        try require(bytes[y * row + p] == 0, "JPEG wrote row padding")
                    } }
                }
                try fromK.image.storage.withUnsafeBytes { bytes in
                    for y in 0..<height { for p in width * 2..<kRow where y * kRow + p < bytes.count {
                        try require(bytes[y * kRow + p] == 0, "J2K wrote row padding")
                    } }
                }
                // Only completed compressed outputs are written for independent
                // oracle checks; no decoded hand-off pixels are written to disk.
                try jpeg.data.write(to: output.appendingPathComponent(name + ".jpg"))
                try j2k.data.write(to: output.appendingPathComponent(name + ".j2k"))
                print("PASS \(name): both directions, exact samples/bytes, shared owners, two readers, sealed mutation rejection, padding, callback cancellation/retry, endian rejection")
            }
        }
    }
}
