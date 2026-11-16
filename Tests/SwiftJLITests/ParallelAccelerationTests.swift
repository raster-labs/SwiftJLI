// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct ParallelAccelerationTests {
    private static func makeImage(descriptor: ImageDescriptor, bytes: [UInt8]) throws -> SwiftJLI.Image {
        try ImageDestination.allocate(descriptor: descriptor).write { out in
            bytes.withUnsafeBytes { src in
                out.copyMemory(from: src)
            }
        }
    }

    private static func makeRGB8Descriptor(width: Int, height: Int) throws -> ImageDescriptor {
        let plane = try PlaneDescriptor(
            width: width, height: height, components: [0, 1, 2],
            sampleStride: 1, pixelStride: 3, rowBytes: width * 3, byteCount: width * height * 3)
        return try ImageDescriptor(
            width: width, height: height, sampleType: .unsignedInteger,
            storageBits: 8, meaningfulBits: 8, components: [.red, .green, .blue],
            colour: .rgb, planes: [plane])
    }

    @Test func synchronousLosslessAndDCTAPIsMatchAsyncBitForBit() async throws {
        let width = 320, height = 256
        let grey16Desc = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: 12)
        var greyBytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            let v = UInt16((i * 73 + (i / width) * 29 + 511) & 0x0FFF)
            greyBytes[i * 2] = UInt8(truncatingIfNeeded: v)
            greyBytes[i * 2 + 1] = UInt8(v >> 8)
        }
        let greyImage = try Self.makeImage(descriptor: grey16Desc, bytes: greyBytes)

        let losslessEncoder = try Encoder(configuration: .init(mode: .lossless, codecOptions: .init(predictor: 1)))
        let asyncEncoded = try await losslessEncoder.encode(greyImage)
        let syncEncoded = try losslessEncoder.encodeSynchronously(greyImage)
        #expect(syncEncoded.data == asyncEncoded.data)

        let decoder = try Decoder()
        let inspected = try decoder.inspectSynchronously(syncEncoded.data)
        #expect(inspected.descriptor.width == width)
        #expect(inspected.descriptor.height == height)
        #expect(inspected.descriptor.meaningfulBits == 12)

        let syncDecoded = try decoder.decodeSynchronously(
            syncEncoded.data,
            options: .init(executionPolicy: .preferred(.accelerated)))
        let decodedBytes = try syncDecoded.image.storage.withUnsafeBytes { Array($0) }
        #expect(decodedBytes == greyBytes)

        let destination = try ImageDestination.allocate(descriptor: grey16Desc)
        let intoDecoded = try decoder.decodeSynchronously(syncEncoded.data, into: destination)
        let intoBytes = try intoDecoded.image.storage.withUnsafeBytes { Array($0) }
        #expect(intoBytes == greyBytes)
        #expect(intoDecoded.report.pixelAllocationCount == 0)

        // DCT lossy synchronous path (accelerated vs scalarCPU)
        let rgb8Desc = try Self.makeRGB8Descriptor(width: 192, height: 144)
        var rgbBytes = [UInt8](repeating: 0, count: 192 * 144 * 3)
        for i in 0..<rgbBytes.count {
            rgbBytes[i] = UInt8(truncatingIfNeeded: i * 37 + 19)
        }
        let rgbImage = try Self.makeImage(descriptor: rgb8Desc, bytes: rgbBytes)
        let dctEncoder = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct: .init(quality: 90))))
        let syncDCT = try dctEncoder.encodeSynchronously(rgbImage)
        let asyncDCT = try await dctEncoder.encode(rgbImage)
        #expect(syncDCT.data == asyncDCT.data)

        let syncDCTDecoded = try decoder.decodeSynchronously(syncDCT.data)
        let asyncDCTDecoded = try await decoder.decode(syncDCT.data)
        let syncDCTBytes = try syncDCTDecoded.image.storage.withUnsafeBytes { Array($0) }
        let asyncDCTBytes = try asyncDCTDecoded.image.storage.withUnsafeBytes { Array($0) }
        #expect(syncDCTBytes == asyncDCTBytes)
    }

    @Test(arguments: [1, 4])
    func parallelRestartLosslessGreyAndRGBMatchSingleWorker(predictor: Int) throws {
        let width = 384, height = 256
        let restartInterval = width * 16 // 16-row restart strips -> 16 segments (width*height >= 65536)

        // 16-bit greyscale
        let greyDesc = try ImageDescriptor.greyscale16(width: width, height: height)
        var greyBytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            let v = UInt16(truncatingIfNeeded: i * 193 + (i / width) * 41 + 9001)
            greyBytes[i * 2] = UInt8(truncatingIfNeeded: v)
            greyBytes[i * 2 + 1] = UInt8(v >> 8)
        }
        let greyImage = try Self.makeImage(descriptor: greyDesc, bytes: greyBytes)
        let encoder = try Encoder(configuration: .init(
            mode: .lossless,
            codecOptions: .init(predictor: predictor, restartInterval: restartInterval)))

        let lim1 = try ResourceLimits(maximumWorkers: 1)
        let lim8 = try ResourceLimits(maximumWorkers: 8)

        let enc1 = try encoder.encodeSynchronously(greyImage, options: .init(resourceLimits: lim1))
        let enc8 = try encoder.encodeSynchronously(greyImage, options: .init(resourceLimits: lim8))
        #expect(enc1.data == enc8.data)

        let decoder = try Decoder()
        let dec1 = try decoder.decodeSynchronously(enc8.data, options: .init(resourceLimits: lim1, executionPolicy: .scalarCPU))
        let dec8 = try decoder.decodeSynchronously(enc8.data, options: .init(resourceLimits: lim8, executionPolicy: .automatic))
        #expect(try dec1.image.storage.withUnsafeBytes { Array($0) } == greyBytes)
        #expect(try dec8.image.storage.withUnsafeBytes { Array($0) } == greyBytes)

        // 8-bit RGB with row-padding sentinels via into: destination
        let rowBytes = width * 3 + 7
        let planeCap = 5 + rowBytes * height
        let totalCap = planeCap + 9
        let rgbPlane = try PlaneDescriptor(
            width: width, height: height, components: [0, 1, 2], offset: 5,
            sampleStride: 1, pixelStride: 3, rowBytes: rowBytes, byteCount: planeCap)
        let paddedRGBDesc = try ImageDescriptor(
            width: width, height: height, sampleType: .unsignedInteger,
            storageBits: 8, meaningfulBits: 8, components: [.red, .green, .blue],
            colour: .rgb, planes: [rgbPlane])

        let packedRGBDesc = try Self.makeRGB8Descriptor(width: width, height: height)
        var rgbBytes = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<rgbBytes.count {
            rgbBytes[i] = UInt8(truncatingIfNeeded: i * 97 + (i / (width * 3)) * 13 + 7)
        }
        let rgbImage = try Self.makeImage(descriptor: packedRGBDesc, bytes: rgbBytes)
        let rgbEnc = try encoder.encodeSynchronously(rgbImage, options: .init(resourceLimits: lim8))

        let rgbDec1 = try decoder.decodeSynchronously(rgbEnc.data, options: .init(resourceLimits: lim1, executionPolicy: .scalarCPU))
        #expect(try rgbDec1.image.storage.withUnsafeBytes { Array($0) } == rgbBytes)

        let owner = try OwnedImageStorage(byteCount: totalCap)
        let dest = try ImageDestination(descriptor: paddedRGBDesc, storage: owner)
        let rgbDec8 = try decoder.decodeSynchronously(
            rgbEnc.data, into: dest,
            options: .init(resourceLimits: lim8, executionPolicy: .automatic))
        try rgbDec8.image.storage.withUnsafeBytes { out in
            for y in 0..<height {
                let start = 5 + y * rowBytes
                let expectedStart = y * width * 3
                #expect(out[start..<(start + width * 3)].elementsEqual(rgbBytes[expectedStart..<(expectedStart + width * 3)]))
            }
        }
    }

    @Test func parallelRestartLosslessRejectsCorruptedSegmentBoundaries() throws {
        let width = 256, height = 256
        let restartInterval = width * 16 // 16 segments, >= 65536 pixels triggers parallel scanRestartMarkers
        let greyDesc = try ImageDescriptor.greyscale16(width: width, height: height)
        var greyBytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            let v = UInt16(truncatingIfNeeded: i * 193 + 17)
            greyBytes[i * 2] = UInt8(truncatingIfNeeded: v)
            greyBytes[i * 2 + 1] = UInt8(v >> 8)
        }
        let greyImage = try Self.makeImage(descriptor: greyDesc, bytes: greyBytes)
        let encoder = try Encoder(configuration: .init(
            mode: .lossless,
            codecOptions: .init(predictor: 1, restartInterval: restartInterval)))
        let encoded = try encoder.encodeSynchronously(greyImage)

        // Case 1: Insert 2 unstuffed trailing bytes immediately before RST0 so scanRestartMarkers still enters
        // the parallel path, and verifySegmentBoundary catches segment 0 ending early identically to 1T!
        var paddedSeg0 = Array(encoded.data)
        var rst0Pos: Int?
        for i in 0..<(paddedSeg0.count - 1) where paddedSeg0[i] == 0xFF && paddedSeg0[i + 1] == 0xD0 {
            rst0Pos = i
            break
        }
        let pos = try #require(rst0Pos)
        paddedSeg0.insert(contentsOf: [0x12, 0x34], at: pos)

        // Case 2: Corrupt RST0 (0xFF 0xD0) into stuffed 0xFF 0x00 so one restart marker is missing.
        var missingRST = Array(encoded.data)
        missingRST[pos + 1] = 0x00

        let decoder = try Decoder()
        let lim1 = try ResourceLimits(maximumWorkers: 1)
        let lim8 = try ResourceLimits(maximumWorkers: 8)
        for badData in [Data(paddedSeg0), Data(missingRST)] {
            #expect(throws: CodecError.self) {
                _ = try decoder.decodeSynchronously(badData, options: .init(resourceLimits: lim1, executionPolicy: .scalarCPU))
            }
            #expect(throws: CodecError.self) {
                _ = try decoder.decodeSynchronously(badData, options: .init(resourceLimits: lim8, executionPolicy: .automatic))
            }
        }
    }

    @Test func rawBitChunkWriterPreservesFull32BitWrite() {
        var writer = JLIEncoder.RawBitChunkWriter(capacity: 64)
        writer.writeBits(0b101, count: 3)
        writer.writeBits(0xDEADBEEF, count: 32)
        writer.writeBits(0b01101, count: 5)
        writer.finish()
        #expect(writer.bitCount == 40)
        // 0b101 (3) + 0xDEADBEEF (32) + 0b01101 (5) = 40 bits = 5 exact bytes:
        // (0b101 << 37) | (0xDEADBEEF << 5) | 0b01101
        let expectedWord: UInt64 = (UInt64(0b101) << 37) | (UInt64(0xDEADBEEF) << 5) | UInt64(0b01101)
        let expectedBytes: [UInt8] = [
            UInt8((expectedWord >> 32) & 0xFF),
            UInt8((expectedWord >> 24) & 0xFF),
            UInt8((expectedWord >> 16) & 0xFF),
            UInt8((expectedWord >> 8) & 0xFF),
            UInt8(expectedWord & 0xFF),
        ]
        #expect(writer.bytes == expectedBytes)
    }
}
