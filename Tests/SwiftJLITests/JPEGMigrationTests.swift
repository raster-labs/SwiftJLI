// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct JPEGMigrationTests {
    @Test(arguments: 2...16, 1...7)
    func sharedLosslessPreservesPrecisionAndPadding(bits: Int, predictor: Int) async throws {
        let width = 9, height = 5, maximum = (1 << bits) - 1
        let packed = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits)
        let padded = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: bits,
                                                    rowBytes: 24, offset: 4)
        func sample(_ x: Int, _ y: Int) -> UInt16 {
            if x == 0 { return 0 }; if x == 1 { return UInt16(maximum) }
            return UInt16(((x * 11731) ^ (y * 31957)) & maximum)
        }
        let a = try ImageDestination.allocate(descriptor: packed).writeUInt16(sample)
        let b = try ImageDestination.allocate(descriptor: padded).writeUInt16(sample)
        let encoder = try SwiftJLI.Encoder(configuration: .init(codecOptions: .init(predictor: predictor, restartInterval: width * 2)))
        let first = try await encoder.encode(a), second = try await encoder.encode(b)
        #expect(first.data == second.data)
        #expect(second.report.copyEvents.isEmpty && second.report.pixelAllocationCount == 0)
        let provider = try OwnedImageStorage(byteCount: padded.requiredByteCount)
        let destination = try ImageDestination(descriptor: padded, storage: provider)
        let decoded = try await SwiftJLI.Decoder().decode(first.data, into: destination)
        #expect(decoded.image.storage.allocationID == provider.allocationID)
        #expect(decoded.image.descriptor.meaningfulBits == bits)
        for y in 0..<height { for x in 0..<width {
            #expect(try decoded.image.sampleUInt16(x: x, y: y) == sample(x, y))
        } }
        // Owned storage initialises padding; the codec never emits source padding.
        try decoded.image.storage.withUnsafeBytes { bytes in
            #expect(bytes[0..<4].allSatisfy { $0 == 0 })
            for y in 0..<height { #expect(bytes[(4 + y * 24 + 18)..<(4 + (y + 1) * 24)].allSatisfy { $0 == 0 }) }
        }
    }

    @Test(arguments: [8, 16])
    func rgbAndMetadata(bits: Int) async throws {
        let bps = bits / 8, row = 4 * 3 * bps
        let plane = try PlaneDescriptor(width: 4, height: 3, components: [0, 1, 2],
            sampleStride: bps, pixelStride: 3 * bps, rowBytes: row, byteCount: row * 3)
        let icc = Data((0..<120).map { UInt8($0) })
        let descriptor = try ImageDescriptor(width: 4, height: 3, storageBits: bits, meaningfulBits: bits,
            components: [.red, .green, .blue], colour: .rgb, planes: [plane], iccProfile: icc)
        let raw = try ImageDestination.allocate(descriptor: descriptor).write { bytes in
            for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i * 71) }
        }
        let metadata = ImageMetadata(entries: ["Exif": Data([73,73,42,0,8,0,0,0])], requiredKeys: ["Exif"])
        let image = try SwiftJLI.Image(descriptor: descriptor, storage: raw.storage, metadata: metadata)
        let encoded = try await SwiftJLI.Encoder().encode(image)
        let decoder = try SwiftJLI.Decoder()
        let info = try decoder.inspect(encoded.data)
        #expect(info.descriptor.iccProfile == icc && info.metadata.entries == metadata.entries)
        let decoded = try await decoder.decode(encoded.data)
        #expect(decoded.image.descriptor == descriptor)
        let before = try image.storage.withUnsafeBytes { Array($0) }
        let after = try decoded.image.storage.withUnsafeBytes { Array($0) }
        #expect(before == after)
        #expect(decoded.report.pixelAllocationCount == 1)
    }

    @Test func limitsInvalidSamplesAndDeadlines() async throws {
        let descriptor = try ImageDescriptor.greyscale16(width: 2, height: 2, meaningfulBits: 12)
        let invalid = try ImageDestination.allocate(descriptor: descriptor).write { $0.initializeMemory(as: UInt8.self, repeating: 255) }
        do { _ = try await SwiftJLI.Encoder().encode(invalid); Issue.record("Out-of-range samples accepted") }
        catch let error as CodecError { #expect(error.category == .invalidArgument) }
        let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { _, _ in 4095 }
        let encoded = try await SwiftJLI.Encoder().encode(image)
        let deadline = try ResourceLimits(deadlineSeconds: Double.leastNonzeroMagnitude)
        do { _ = try await SwiftJLI.Decoder().decode(encoded.data, options: .init(resourceLimits: deadline)); Issue.record("Expired deadline accepted") }
        catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        let tiny = try ResourceLimits(maximumWorkspaceBytes: 1)
        do { _ = try await SwiftJLI.Decoder().decode(encoded.data, options: .init(resourceLimits: tiny)); Issue.record("Workspace limit ignored") }
        catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
    }

    @Test func envelopeRejectsTruncationAndForgedLengths() async throws {
        let image = try ImageDestination.allocate(descriptor: .greyscale16(width: 1, height: 1)).writeUInt16 { _, _ in 65535 }
        let encoded = try await SwiftJLI.Encoder().encode(image)
        let decoder = try SwiftJLI.Decoder()
        for n in 0..<encoded.data.count {
            #expect(throws: CodecError.self) { try decoder.inspect(Data(encoded.data.prefix(n))) }
        }
        var bytes = Array(encoded.data)
        let sof = try #require((0..<(bytes.count - 1)).first { bytes[$0] == 255 && bytes[$0 + 1] == 195 })
        bytes[sof + 2] = 0; bytes[sof + 3] = 2
        #expect(throws: CodecError.self) { try decoder.inspect(Data(bytes)) }
    }

    @Test func iccMD5StandardVectors() {
        let vectors = [("", "d41d8cd98f00b204e9800998ecf8427e"), ("abc", "900150983cd24fb0d6963f7d28e17f72"),
                       ("message digest", "f96b697d7cb7938d525a2f31aaf161d0")]
        for (message, expected) in vectors {
            let actual = ICCProfileMD5.digest(Array(message.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(actual == expected)
        }
    }
}
