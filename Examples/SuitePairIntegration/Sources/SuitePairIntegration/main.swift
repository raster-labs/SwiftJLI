// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
import SwiftJ2K
import SwiftJLS
import SwiftJXL
#if canImport(HeapProbe)
import HeapProbe
#endif

private struct Failure: Error { let message: String }
private func check(_ value: Bool, _ message: String) throws {
    if !value { throw Failure(message: message) }
}
private func layoutError(_ error: any Error) -> Bool {
    if let e = error as? SwiftJLI.CodecError { return e.category == .incompatibleImageLayout }
    if let e = error as? SwiftJ2K.CodecError { return e.category == .incompatibleImageLayout }
    if let e = error as? SwiftJLS.CodecError { return e.category == .incompatibleImageLayout }
    if let e = error as? SwiftJXL.CodecError { return e.category == .incompatibleImageLayout }
    return false
}
private struct Shape: Sendable {
    let width: Int, height: Int, bits: Int, row: Int
    var capacity: Int { row * height }
}
// The enum retains the concrete owner. The reader exposes only scoped reads;
// it stores no pointer, pixel array, mutable lease or escaping buffer closure.
private enum Owner: Sendable {
    case jli(SwiftJLI.OwnedImageStorage, SwiftJLI.ImageDestination)
    case j2k(SwiftJ2K.OwnedImageStorage, SwiftJ2K.ImageDestination)
    case jls(SwiftJLS.OwnedImageStorage, SwiftJLS.ImageDestination)
    case jxl(SwiftJXL.OwnedImageStorage, SwiftJXL.ImageDestination)
    var byteCount: Int { switch self {
        case .jli(let owner, _): return owner.byteCount
        case .j2k(let owner, _): return owner.byteCount
        case .jls(let owner, _): return owner.byteCount
        case .jxl(let owner, _): return owner.byteCount
    } }
    var allocationID: UUID { switch self {
        case .jli(let owner, _): return owner.allocationID
        case .j2k(let owner, _): return owner.allocationID
        case .jls(let owner, _): return owner.allocationID
        case .jxl(let owner, _): return owner.allocationID
    } }
    func requireSealed() throws { switch self {
        case .jli(let owner, _):
            do { _ = try owner.reserveWrite(); throw Failure(message: "Sealed jli owner admitted mutation") }
            catch is SwiftJLI.CodecError { }
        case .j2k(let owner, _):
            do { _ = try owner.reserveWrite(); throw Failure(message: "Sealed j2k owner admitted mutation") }
            catch is SwiftJ2K.CodecError { }
        case .jls(let owner, _):
            do { _ = try owner.reserveWrite(); throw Failure(message: "Sealed jls owner admitted mutation") }
            catch is SwiftJLS.CodecError { }
        case .jxl(let owner, _):
            do { _ = try owner.reserveWrite(); throw Failure(message: "Sealed jxl owner admitted mutation") }
            catch is SwiftJXL.CodecError { }
    } }
}
private enum SealedOwner: Sendable {
    case jli(any SwiftJLI.ReadOnlyImageStorage)
    case j2k(any SwiftJ2K.ReadOnlyImageStorage)
    case jls(any SwiftJLS.ReadOnlyImageStorage)
    case jxl(any SwiftJXL.ReadOnlyImageStorage)
    var byteCount: Int { switch self {
        case .jli(let owner): return owner.byteCount
        case .j2k(let owner): return owner.byteCount
        case .jls(let owner): return owner.byteCount
        case .jxl(let owner): return owner.byteCount
    } }
    var allocationID: UUID { switch self {
        case .jli(let owner): return owner.allocationID
        case .j2k(let owner): return owner.allocationID
        case .jls(let owner): return owner.allocationID
        case .jxl(let owner): return owner.allocationID
    } }
    func read<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R { switch self {
        case .jli(let owner): return try owner.withUnsafeBytes(body)
        case .j2k(let owner): return try owner.withUnsafeBytes(body)
        case .jls(let owner): return try owner.withUnsafeBytes(body)
        case .jxl(let owner): return try owner.withUnsafeBytes(body)
    } }
}
private struct Reader: SwiftJLI.ReadOnlyImageStorage, SwiftJ2K.ReadOnlyImageStorage, SwiftJLS.ReadOnlyImageStorage, SwiftJXL.ReadOnlyImageStorage {
    let owner: SealedOwner
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R { try owner.read(body) }
}
private enum Codec: String, CaseIterable, Sendable {
    case jli, j2k, jls, jxl
    var suffix: String { self == .jli ? "jpg" : rawValue }
    func allocate(_ s: Shape) throws -> Owner { switch self {
        case .jli:
            let storage = try SwiftJLI.OwnedImageStorage(byteCount: s.capacity)
            let descriptor = try SwiftJLI.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            return .jli(storage, try SwiftJLI.ImageDestination(descriptor: descriptor, storage: storage))
        case .j2k:
            let storage = try SwiftJ2K.OwnedImageStorage(byteCount: s.capacity)
            let descriptor = try SwiftJ2K.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            return .j2k(storage, try SwiftJ2K.ImageDestination(descriptor: descriptor, storage: storage))
        case .jls:
            let storage = try SwiftJLS.OwnedImageStorage(byteCount: s.capacity)
            let descriptor = try SwiftJLS.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            return .jls(storage, try SwiftJLS.ImageDestination(descriptor: descriptor, storage: storage))
        case .jxl:
            let storage = try SwiftJXL.OwnedImageStorage(byteCount: s.capacity)
            let descriptor = try SwiftJXL.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            return .jxl(storage, try SwiftJXL.ImageDestination(descriptor: descriptor, storage: storage))
    } }
    func encode(_ source: Reader, _ s: Shape, cancel: Bool = false) async throws -> Data { switch self {
        case .jli:
            let d = try SwiftJLI.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            let image = try SwiftJLI.Image(descriptor: d, storage: source)
            let result = try await SwiftJLI.Encoder().encode(image, options: .init(progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "jli encode copied pixels")
            return result.data
        case .j2k:
            let d = try SwiftJ2K.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            let image = try SwiftJ2K.Image(descriptor: d, storage: source)
            let result = try await SwiftJ2K.Encoder().encode(image, options: .init(progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "j2k encode copied pixels")
            return result.data
        case .jls:
            let d = try SwiftJLS.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            let image = try SwiftJLS.Image(descriptor: d, storage: source)
            let result = try await SwiftJLS.Encoder().encode(image, options: .init(progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "jls encode copied pixels")
            return result.data
        // SwiftJXL reports allocation counts as unknown; the Linux heap controls
        // independently measure the destination and detect an injected full-frame copy.
        case .jxl:
            let d = try SwiftJXL.ImageDescriptor.greyscale16(width: s.width, height: s.height, meaningfulBits: s.bits, rowBytes: s.row)
            let image = try SwiftJXL.Image(descriptor: d, storage: source)
            let result = try await SwiftJXL.Encoder().encode(image, options: .init(progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == nil, "jxl reporting contract changed")
            return result.data
    } }
    func decode(_ data: Data, into owner: Owner, _ s: Shape, cancel: Bool = false, allowCopy: Bool = false) async throws -> Reader { switch (self, owner) {
        case (.jli, .jli(let storage, let destination)):
            let result = try await SwiftJLI.Decoder().decode(data, into: destination, options: .init(copyPolicy: allowCopy ? .allowCopy : .requireSharedStorage, progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.image.storage.allocationID == storage.allocationID && result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "jli decode changed owner or copied pixels")
            return Reader(owner: .jli(result.image.storage))
        case (.j2k, .j2k(let storage, let destination)):
            let result = try await SwiftJ2K.Decoder().decode(data, into: destination, options: .init(copyPolicy: allowCopy ? .allowCopy : .requireSharedStorage, progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.image.storage.allocationID == storage.allocationID && result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "j2k decode changed owner or copied pixels")
            return Reader(owner: .j2k(result.image.storage))
        case (.jls, .jls(let storage, let destination)):
            let result = try await SwiftJLS.Decoder().decode(data, into: destination, options: .init(copyPolicy: allowCopy ? .allowCopy : .requireSharedStorage, progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.image.storage.allocationID == storage.allocationID && result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == 0, "jls decode changed owner or copied pixels")
            return Reader(owner: .jls(result.image.storage))
        case (.jxl, .jxl(let storage, let destination)):
            let result = try await SwiftJXL.Decoder().decode(data, into: destination, options: .init(copyPolicy: allowCopy ? .allowCopy : .requireSharedStorage, progress: { _ in
                if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            }))
            try check(result.image.storage.allocationID == storage.allocationID && result.report.copyEvents.isEmpty && result.report.pixelAllocationCount == nil, "jxl decode changed owner or reporting contract")
            return Reader(owner: .jxl(result.image.storage))
        default: throw Failure(message: "Owner and codec differ")
    } }
}
private func sample(_ x: Int, _ y: Int, _ bits: Int) -> UInt16 {
    let maximum = (1 << bits) - 1
    return UInt16(x == 0 && y == 0 ? 0 : x == 1 && y == 0 ? maximum : (x * 193 + y * 357 + x * y * 17) & maximum)
}
private func verify(_ reader: Reader, _ s: Shape) throws {
    try reader.withUnsafeBytes { bytes in
        for y in 0..<s.height {
            for x in 0..<s.width {
                let p = y * s.row + x * 2
                try check(UInt16(bytes[p]) | UInt16(bytes[p + 1]) << 8 == sample(x, y, s.bits), "Sample or meaningful precision changed")
            }
            for x in s.width * 2..<s.row { try check(bytes[y * s.row + x] == 0, "Row padding written") }
        }
    }
}
private func heapStart() {
    #if canImport(HeapProbe)
    hp_begin()
    #endif
}
private func heapEnd(_ direction: String, _ name: String, _ reader: Reader) throws {
    #if canImport(HeapProbe)
    let control = ProcessInfo.processInfo.environment["SWIFTJLI_COPY_CONTROL"] == "1"
    let copy = control ? try reader.withUnsafeBytes { Array($0) } : nil
    let stats = withExtendedLifetime(copy) { hp_end() }
    try check(stats.overflow == 0, "Heap tracker overflow")
    let sizes = (0..<hp_bucket_count()).map { hp_bucket($0) }.map { ["requestedBytes": $0.size, "count": $0.count] }
    let json = try JSONSerialization.data(withJSONObject: ["event": "heap", "direction": direction, "case": name,
        "destinationCapacity": reader.byteCount, "controlCopy": control, "peakRequestedBytes": stats.peak_bytes,
        "liveRequestedBytes": stats.live_bytes, "allocationSizes": sizes], options: .sortedKeys)
    print(String(decoding: json, as: UTF8.self))
    #endif
}
@main struct SuitePairIntegration {
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        #if canImport(HeapProbe)
        try check(hp_calibrate() == 1, "C heap calibration failed")
        hp_begin()
        let calibration = try SwiftJLI.OwnedImageStorage(byteCount: 1_048_576)
        let stats = hp_end()
        let bins = (0..<hp_bucket_count()).map { hp_bucket($0) }.filter { $0.size >= 1_048_576 }
        try check(stats.peak_bytes >= 1_048_576 && bins.count == 1, "Swift heap calibration failed")
        print("{\"event\":\"calibration\",\"arrayHeaderBytes\":\(Int(bins[0].size) - calibration.byteCount)}")
        #endif
        for bits in [12, 16] { for (width, height) in [(19, 13), (65, 31), (257, 17)] {
            let sourceShape = Shape(width: width, height: height, bits: bits, row: width * 2 + 14)
            let targetShape = Shape(width: width, height: height, bits: bits, row: width * 2 + 22)
            let name = "\(width)x\(height)-u\(bits)"
            let storage = try SwiftJLI.OwnedImageStorage(byteCount: sourceShape.capacity)
            let d = try SwiftJLI.ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits, rowBytes: sourceShape.row)
            let sourceImage = try SwiftJLI.ImageDestination(descriptor: d, storage: storage).write { bytes in
                bytes.initializeMemory(as: UInt8.self, repeating: 0xa5)
                for y in 0..<height { for x in 0..<width {
                    let value = sample(x, y, bits), p = y * sourceShape.row + x * 2
                    bytes[p] = UInt8(truncatingIfNeeded: value); bytes[p + 1] = UInt8(value >> 8)
                } }
            }
            let original = Reader(owner: .jli(sourceImage.storage))
            var streams: [Codec: Data] = [:]
            for codec in Codec.allCases {
                FileHandle.standardError.write(Data("Preparing \(name) \(codec.rawValue)\n".utf8))
                streams[codec] = try await codec.encode(original, sourceShape)
                let cancelled = await Task {
                    do { _ = try await codec.encode(original, sourceShape, cancel: true); return false }
                    catch is CancellationError { return true } catch { return false }
                }.value
                try check(cancelled, "Cancelled encode succeeded: \(codec)")
                let retryOwner = try codec.allocate(targetShape), data = streams[codec]!
                let cancelledDecode = await Task {
                    do { _ = try await codec.decode(data, into: retryOwner, targetShape, cancel: true); return false }
                    catch is CancellationError { return true } catch { return false }
                }.value
                try check(cancelledDecode, "Cancelled decode succeeded: \(codec)")
                FileHandle.standardError.write(Data("Retrying cancelled destination \(codec.rawValue)\n".utf8))
                let retried = try await codec.decode(data, into: retryOwner, targetShape)
                try verify(retried, targetShape)
                for allowCopy in [false, true] {
                    let wrong = Shape(width: width + 1, height: height, bits: bits, row: targetShape.row)
                    let owner = try codec.allocate(wrong)
                    do { _ = try await codec.decode(data, into: owner, wrong, allowCopy: allowCopy); throw Failure(message: "Mismatched dimensions accepted") }
                    catch let error as Failure { throw error }
                    catch { try check(layoutError(error), "Unexpected descriptor rejection: \(error)") }
                }
            }
            for from in Codec.allCases { for to in Codec.allCases where to != from {
                let input = streams[from]!, expected = streams[to]!
                heapStart()
                let owner = try from.allocate(targetShape)
                let reader = try await from.decode(input, into: owner, targetShape)
                async let first = to.encode(reader, targetShape)
                async let second = to.encode(reader, targetShape)
                let (a, b) = try await (first, second)
                let direction = from.rawValue + "-to-" + to.rawValue
                try heapEnd(direction, name, reader)
                try check(a == b && a == expected, "Codestream changed across shared hand-off")
                try owner.requireSealed()
                try verify(reader, targetShape)
                try a.write(to: output.appendingPathComponent(name + "-" + direction + "." + to.suffix))
                print("PASS \(name) \(direction): exact samples/bytes, shared owner, concurrent readers, padding and sealed mutation rejection")
            } }
        } }
    }
}
