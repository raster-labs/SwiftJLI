// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

/// JLISwift a250354 / 981da4e regression cases, exercised through the common API.
@Suite struct JPEGDecodeParityTests {
    @Test func centredChromaAgreesAcrossWorkerLimits() throws {
        let width = 257, height = 129
        let input = (0..<(width * height)).map { Float(($0 * 71) % 256) + 0.375 }
        for vertical in [1, 2] {
            func reconstruct(workers: Int) throws -> [Float] {
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: .scalarCPU, maximumWorkers: workers)) {
                    try ChromaSampling.upsampleJPEG(input, width: width, height: height,
                        targetWidth: 513, targetHeight: vertical == 1 ? height : 257,
                        horizontalSampling: 1, verticalSampling: 1,
                        maximumHorizontalSampling: 2, maximumVerticalSampling: vertical)
                }
            }
            #expect(try reconstruct(workers: 1) == reconstruct(workers: 4))
        }
    }
    @Test(arguments: ChromaReferenceFixtures.all)
    func independentChroma(_ fixture: ChromaReferenceFixtures.Fixture) async throws {
        let jpeg = try #require(Data(base64Encoded: fixture.jpeg))
        let reference = try #require(Data(base64Encoded: fixture.rgb))
        for policy: ExecutionPolicy in [.scalarCPU, .automatic] {
            let decoder = try Decoder()
            let result = try await decoder.decode(jpeg, options: .init(executionPolicy: policy))
            let d = result.image.descriptor
            #expect(d.width == fixture.width && d.height == fixture.height)
            #expect(d.colour == .rgb && d.storageBits == 8)
            let actual = try result.image.storage.withUnsafeBytes { Array($0) }
            try #require(actual.count == reference.count)
            let maximum = zip(actual, reference).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(maximum <= 3, "\(fixture.name): RGB channel error \(maximum) exceeds 3")

            let row = d.width * 3 + 7, offset = 5
            let plane = try PlaneDescriptor(width: d.width, height: d.height, components: [0,1,2], offset: offset,
                sampleStride: 1, pixelStride: 3, rowBytes: row, byteCount: row * d.height)
            let padded = try ImageDescriptor(width: d.width, height: d.height, storageBits: 8,
                meaningfulBits: 8, components: [.red,.green,.blue], colour: .rgb, planes: [plane])
            let storage = try OwnedImageStorage(byteCount: padded.requiredByteCount)
            let supplied = try await decoder.decode(jpeg, into: .init(descriptor: padded, storage: storage),
                options: .init(executionPolicy: policy))
            #expect(supplied.image.storage.allocationID == storage.allocationID)
            #expect(supplied.report.copyEvents.isEmpty && supplied.report.pixelAllocationCount == 0)
            try supplied.image.storage.withUnsafeBytes { bytes in
                #expect(bytes.prefix(offset).allSatisfy { $0 == 0 })
                for y in 0..<d.height {
                    #expect(bytes[(offset + y * row)..<(offset + y * row + d.width * 3)]
                        .elementsEqual(actual[(y * d.width * 3)..<((y + 1) * d.width * 3)]))
                    #expect(bytes[(offset + y * row + d.width * 3)..<min(bytes.count, offset + (y + 1) * row)].allSatisfy { $0 == 0 })
                }
            }
        }
    }

    private func grey() throws -> [UInt8] {
        try JLIEncoder().encode(JLIImage(width: 8, height: 8, pixelFormat: .uint8,
            colorModel: .grayscale, data: [UInt8](repeating: 73, count: 64)))
    }

    @Test func boundedCompleteCodestreamAndPadding() async throws {
        let stream = try grey(), decoder = try Decoder()
        let odd = stream.count.isMultiple(of: 2)
            ? Array(stream.prefix(2)) + [255,224,0,3,0] + Array(stream.dropFirst(2)) : stream
        let even = odd + [0]
        let evenUnpadded = stream.count.isMultiple(of: 2) ? stream
            : Array(stream.prefix(2)) + [255,224,0,3,0] + Array(stream.dropFirst(2))
        for bytes in [odd, even] {
            _ = try decoder.inspect(Data(bytes))
            let result = try await decoder.decode(Data(bytes))
            #expect(try result.image.storage.withUnsafeBytes { Array($0) } == [UInt8](repeating: 73, count: 64))
        }
        let invalidStreams: [[UInt8]] = [
            Array(stream.dropLast(2)), stream + stream, stream + [1,2],
            odd + [1], odd + [0,0], even + [0], evenUnpadded + [0]
        ]
        for bytes in invalidStreams {
            do { _ = try await decoder.decode(Data(bytes)); Issue.record("Accepted invalid trailing data") }
            catch let error as CodecError { #expect(error.category == .malformedInput) }
        }
        for limits in [try ResourceLimits(maximumCompressedBytes: 2),
                       try ResourceLimits(maximumPixels: 63), try ResourceLimits(maximumDecodedBytes: 63)] {
            do { _ = try await decoder.decode(Data(stream), options: .init(resourceLimits: limits)); Issue.record("Ignored limit") }
            catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        }
    }

    @Test(arguments: [8, 12])
    func rawRGBAdobe(precision: Int) async throws {
        let values = precision == 8 ? [210,70,25] : [2000,2048,2048]
        let input = precision == 8 ? values : [2000,2000,2000]
        let bps = precision == 8 ? 1 : 2
        let samples: [UInt8] = (0..<64).flatMap { _ in input.flatMap { value in
            bps == 1 ? [UInt8(value)] : [UInt8(value & 255), UInt8(value >> 8)]
        } }
        let source = try JLIImage(width: 8, height: 8, pixelFormat: bps == 1 ? .uint8 : .uint16,
            colorModel: precision == 8 ? .yCbCr : .rgb, data: samples)
        var cfg = JLIEncoderConfiguration.default
        cfg.quality = 100; cfg.chromaSubsampling = .yuv444
        let encoded = try JLIEncoder().encode(source, configuration: cfg)
        let adobe: [UInt8] = [255,238,0,14,65,100,111,98,101,0,100,0,0,0,0,0]
        let bytes = Data(Array(encoded.prefix(2)) + adobe + Array(encoded.dropFirst(2)))
        for scale in [1,2,4,8] {
            for policy: ExecutionPolicy in [.scalarCPU, .automatic] {
                let decoder = try Decoder(configuration: .init(scale: scale))
                #expect(try decoder.inspect(bytes).descriptor.colour == .rgb)
                let result = try await decoder.decode(bytes, options: .init(executionPolicy: policy))
                #expect(result.image.descriptor.meaningfulBits == precision)
                try result.image.storage.withUnsafeBytes { raw in
                    for p in stride(from: 0, to: raw.count, by: bps) {
                        let actual = Int(raw[p]) | (bps == 2 ? Int(raw[p + 1]) << 8 : 0)
                        #expect(abs(actual - values[(p / bps) % 3]) <= 1)
                    }
                }
                let d = result.image.descriptor, row = d.width * 3 * bps + 8
                let plane = try PlaneDescriptor(width: d.width, height: d.height, components: [0,1,2], offset: 4,
                    sampleStride: bps, pixelStride: 3 * bps, rowBytes: row, byteCount: row * d.height)
                let padded = try ImageDescriptor(width: d.width, height: d.height, storageBits: bps * 8,
                    meaningfulBits: precision, components: [.red,.green,.blue], colour: .rgb, planes: [plane])
                let storage = try OwnedImageStorage(byteCount: padded.requiredByteCount)
                let borrowed = try await decoder.decode(bytes, into: .init(descriptor: padded, storage: storage),
                    options: .init(executionPolicy: policy))
                #expect(borrowed.image.storage.allocationID == storage.allocationID)
                #expect(borrowed.report.pixelAllocationCount == 0 && borrowed.report.copyEvents.isEmpty)
                let packed = try result.image.storage.withUnsafeBytes { Array($0) }
                try borrowed.image.storage.withUnsafeBytes { raw in
                    #expect(raw.prefix(4).allSatisfy { $0 == 0 })
                    for y in 0..<d.height {
                        let payload = d.width * 3 * bps, start = 4 + y * row
                        #expect(raw[start..<(start + payload)].elementsEqual(packed[(y * payload)..<((y + 1) * payload)]))
                        #expect(raw[(start + payload)..<min(raw.count, start + row)].allSatisfy { $0 == 0 })
                    }
                }
            }
        }
    }

    @Test func rawRGBIdentifiersAndSourceOverride() async throws {
        let source = try JLIImage(width: 8, height: 8, pixelFormat: .uint8, colorModel: .yCbCr,
            data: (0..<64).flatMap { _ in [UInt8(210),70,25] })
        var cfg = JLIEncoderConfiguration.default
        cfg.quality = 100; cfg.chromaSubsampling = .yuv444
        let stream = try JLIEncoder().encode(source, configuration: cfg)
        var ids = stream, p = 2
        while p + 3 < ids.count {
            let marker = ids[p + 1], length = Int(ids[p + 2]) * 256 + Int(ids[p + 3])
            if (0xc0...0xc2).contains(marker) {
                for c in 0..<3 { ids[p + 10 + c * 3] = [82,71,66][c] }
            }
            if marker == 0xda {
                for c in 0..<3 { ids[p + 5 + c * 2] = [82,71,66][c] }
                break
            }
            p += length + 2
        }
        let decoder = try Decoder(configuration: .init(sourceColourModel: .rgb))
        for (bytes, selected) in [(ids, try Decoder()), (stream, decoder)] {
            #expect(try selected.inspect(Data(bytes)).descriptor.colour == .rgb)
            #expect(try selected.inspectJPEG(Data(bytes)).imageInfo.descriptor.colour == .rgb)
            let result = try await selected.decode(Data(bytes))
            let samples = try result.image.storage.withUnsafeBytes { Array($0) }
            #expect(zip(samples, source.data).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }
        // Explicit YCbCr on an unmarked stream preserves the normal interpretation.
        let ycbcr = try await Decoder(configuration: .init(sourceColourModel: .yCbCr)).decode(Data(stream))
        let automatic = try await Decoder().decode(Data(stream))
        #expect(try ycbcr.image.storage.withUnsafeBytes { Array($0) } == automatic.image.storage.withUnsafeBytes { Array($0) })

        let adobe: [UInt8] = [255,238,0,14,65,100,111,98,101,0,100,0,0,0,0,0]
        let signalled = Data(Array(stream.prefix(2)) + adobe + Array(stream.dropFirst(2)))
        for bytes in [Data(try grey()), signalled] {
            #expect(throws: CodecError.self) { try decoder.inspect(bytes) }
            #expect(throws: CodecError.self) { try decoder.inspectJPEG(bytes) }
            do { _ = try await decoder.decode(bytes); Issue.record("Override ignored or contradicted metadata") }
            catch let error as CodecError { #expect(error.category == .unsupportedFeature) }
        }
        var conflicting = adobe; conflicting[15] = 1
        let conflict = Data(Array(ids.prefix(2)) + conflicting + Array(ids.dropFirst(2)))
        #expect(throws: CodecError.self) { try Decoder().inspect(conflict) }
    }
}

extension ChromaReferenceFixtures.Fixture: CustomTestStringConvertible {
    var testDescription: String { name }
}
