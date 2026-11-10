// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class TinyDCObservedStorage: WritableImageStorage {
    struct Events {
        var borrows = 0
        var seals = 0
        var aborts = 0
        var bytes: [UInt8] = []
    }
    let owner: OwnedImageStorage
    let events = Mutex(Events())
    init(byteCount: Int) throws { owner = try OwnedImageStorage(byteCount: byteCount) }
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
                                  _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        events.withLock { $0.borrows += 1 }
        return try owner.withUnsafeMutableBytes(lease: lease) { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: 0xA5)
            defer { events.withLock { $0.bytes = Array(bytes) } }
            return try body(bytes)
        }
    }
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage {
        events.withLock { $0.seals += 1 }
        return try owner.finishAndSeal(lease: lease)
    }
    func abortAndInvalidate(lease: StorageWriteLease) throws {
        events.withLock { $0.aborts += 1 }
        try owner.abortAndInvalidate(lease: lease)
    }
}

@Suite struct TinyDCOutputTests {
    private struct Fixture {
        let jpeg: Data
        let parsed: ParsedJPEG
        let width: Int
        let height: Int
    }

    /// Original synthetic sequential JPEG: one EOB code proves compact-DC
    /// admission, while signed DC values exercise fractional and clipped output.
    /// Odd dimensions retain partial right/bottom blocks at both size thresholds.
    private func fixture(blocks: Int, precision: Int, quantiser: UInt8 = 255,
                         restart: Int = 0, replacementEntropy: [UInt8]? = nil) throws -> Fixture {
        let geometry: (Int, Int)
        switch blocks {
        case 1: geometry = (7, 5)
        case 9: geometry = (23, 21)
        case 16: geometry = (31, 29)
        case 17: geometry = (133, 7)
        default: throw JLIError.decodingFailed("Invalid tiny test geometry")
        }
        let (width, height) = geometry
        let dc = StandardHuffmanTables.dcLuminance
        let acBits: [UInt8] = [1] + Array(repeating: 0, count: 15)
        let ac = HuffmanTable(bits: acBits, values: [0])
        let amplitudes: [Int32] = [-255, 255, 0, 1, -1, 17, -17, 127, -127]
        var writer = BitWriter(estimatedMaxSize: 128), previous: Int32 = 0
        for block in 0..<blocks {
            if restart > 0, block > 0, block % restart == 0 {
                writer.emitRestartMarker((block / restart - 1) & 7)
                previous = 0
            }
            let value = amplitudes[block % amplitudes.count]
            HuffmanEncoder.encodeDC(value - previous, table: dc, writer: &writer)
            writer.writeBits(UInt32(ac.encodingTable[0].code), count: Int(ac.encodingTable[0].length))
            previous = value
        }
        writer.flush()
        let entropy = replacementEntropy ?? writer.data
        var markers = MarkerWriter()
        markers.writeSOI()
        markers.writeDQT(tables: [(0, Array(repeating: quantiser, count: 64))])
        markers.writeSOF(progressive: false, precision: precision, width: width, height: height,
            components: [(1, 1, 1, 0)])
        markers.writeDHT(tables: [(0, 0, dc.bits, dc.values), (1, 0, acBits, [0])])
        if restart > 0 { markers.writeDRI(interval: restart) }
        markers.writeSOS(components: [(1, 0, 0)])
        markers.writeEntropyData(entropy)
        markers.writeEOI()
        var parser = MarkerReader(data: markers.data)
        return Fixture(jpeg: Data(markers.data), parsed: try parser.parse(),
            width: width, height: height)
    }

    private func admittedPlan(_ fixture: Fixture, precision: Int, floating: Bool,
                              backend: Backend, blocks: Int) throws -> SequentialGreyscalePlan {
        let plan = try #require(try SequentialGreyscalePlan.make(parsed: fixture.parsed,
            configuration: .init(outputPixelFormat: floating ? .float32 : nil),
            hasDestination: true, normaliseXYBOutput: false, workerLimit: 8, backend: backend))
        #expect(plan.blockCount == blocks && plan.batchBlocks == blocks)
        #expect(plan.dcOnlyTable && !plan.blockLocalIDCT && !plan.pipelined)
        #expect(plan.workspaceBytes == blocks * 8)
        #expect(fixture.parsed.frameInfo.precision == precision)
        return plan
    }

    private func reference(_ fixture: Fixture, floating: Bool, backend: Backend) throws -> [UInt8] {
        try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 1)) {
            // Absence of a destination excludes SequentialGreyscalePlan. This
            // retains the full coefficient/Float plane, not the tiny helper.
            try JLIDecoder().decodeParsed(fixture.parsed,
                configuration: .init(outputPixelFormat: floating ? .float32 : nil)).data
        }
    }

    private func padded(_ packed: [UInt8], width: Int, height: Int, bps: Int,
                        offset: Int, rowBytes: Int, suffix: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0xA5, count: offset + rowBytes * height + suffix)
        for row in 0..<height {
            let start = offset + row * rowBytes, payload = width * bps
            result.replaceSubrange(start..<(start + payload),
                with: packed[(row * payload)..<((row + 1) * payload)])
        }
        return result
    }

    @Test(arguments: [8, 12], [false, true])
    func publicIntegerAndFloatOutputsMatchFullPlanesAcrossTinyThreshold(precision: Int, floating: Bool) async throws {
        let bps = floating ? 4 : precision == 8 ? 1 : 2
        let decoder = try Decoder(configuration: .init(sampleFormat: floating ? .float32RawSamples : .nativeInteger))
        for blocks in [1, 9, 16, 17] {
            let restart = blocks == 1 ? 0 : blocks == 9 ? 3 : blocks - 1
            for quantiser: UInt8 in [1, 255] {
                let sample = try fixture(blocks: blocks, precision: precision, quantiser: quantiser, restart: restart)
                for backend in Decoder.capabilities.availableBackends {
                    _ = try admittedPlan(sample, precision: precision, floating: floating, backend: backend, blocks: blocks)
                    let expected = try reference(sample, floating: floating, backend: backend)
                    let offset = 3 * bps, rowBytes = (sample.width + 3) * bps, suffix = 7
                    let expectedPadded = padded(expected, width: sample.width, height: sample.height,
                        bps: bps, offset: offset, rowBytes: rowBytes, suffix: suffix)
                    let plane = try PlaneDescriptor(width: sample.width, height: sample.height, offset: offset,
                        sampleStride: bps, pixelStride: bps, rowBytes: rowBytes,
                        byteCount: offset + rowBytes * sample.height)
                    let descriptor = try ImageDescriptor(width: sample.width, height: sample.height,
                        sampleType: floating ? .floatingPoint : .unsignedInteger, storageBits: bps * 8,
                        meaningfulBits: floating ? 32 : precision, planes: [plane])
                    let storage = try TinyDCObservedStorage(byteCount: expectedPadded.count)
                    let destination = try ImageDestination(descriptor: descriptor, storage: storage)
                    let options = DecodeOptions(resourceLimits: try ResourceLimits(maximumWorkers: 8),
                        executionPolicy: .required(backend))
                    let direct = try await decoder.decode(sample.jpeg, into: destination, options: options)
                    #expect(direct.image.storage.allocationID == storage.allocationID)
                    #expect(direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty)
                    #expect(direct.report.backend == backend)
                    let events = storage.events.withLock { $0 }
                    #expect(events.borrows == 1 && events.seals == 1 && events.aborts == 0)
                    #expect(events.bytes == expectedPadded)
                    #expect(throws: CodecError.self) { _ = try storage.reserveWrite() }

                    // A second decode finishes its own temporary storage before
                    // either retained image is read. Both must own stable output.
                    let allocated = try await decoder.decode(sample.jpeg, options: options)
                    #expect(allocated.report.pixelAllocationCount == 1 && allocated.report.copyEvents.isEmpty)
                    #expect(try allocated.image.storage.withUnsafeBytes { Array($0) } == expected)
                    #expect(try direct.image.storage.withUnsafeBytes { Array($0) } == expectedPadded)
                    if quantiser == 255 {
                        // -255 and +255 DC with q=255 clip at both sample limits.
                        #expect(expected.prefix(bps).allSatisfy { $0 == 0 })
                        if blocks > 1 {
                            let maximum = floating ? Float((1 << precision) - 1).bitPattern : UInt32((1 << precision) - 1)
                            let maximumBytes = (0..<bps).map { UInt8(truncatingIfNeeded: maximum >> ($0 * 8)) }
                            #expect(expected[(8 * bps)..<(9 * bps)].elementsEqual(maximumBytes))
                        }
                    }
                }
            }
        }
    }

    @Test(arguments: [8, 12], [false, true])
    func cancellationAtFirstOutputPollPreservesDestinationAndAllowsImmediateReuse(precision: Int, floating: Bool) throws {
        let bps = floating ? 4 : precision == 8 ? 1 : 2
        let blocks = 16
        for backend in Decoder.capabilities.availableBackends {
            let sample = try fixture(blocks: blocks, precision: precision, restart: 3)
            let scan = sample.parsed.scans[0]
            let dc = try #require(scan.dcTables[0]), ac = try #require(scan.acTables[0])
            let plan = try admittedPlan(sample, precision: precision, floating: floating, backend: backend, blocks: blocks)
            let expected = try reference(sample, floating: floating, backend: backend)
            let rowBytes = sample.width * bps + 7, offset = 3, suffix = 5
            var output = padded(expected, width: sample.width, height: sample.height,
                bps: bps, offset: offset, rowBytes: rowBytes, suffix: suffix).map { _ in UInt8(0xA5) }
            let polls = Mutex(0)
            // One entry check, one entropy poll per block row, then the writer's
            // first poll. Reconstruction has completed when cancellation fires.
            let stopAt = plan.blockRows + 2
            var reader = BitReader(data: scan.entropyData)
            #expect(throws: CancellationError.self) {
                try NativeOperation.withSynchronousCancellation({
                    if polls.withLock({ $0 += 1; return $0 }) == stopAt { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 8)) {
                        try output.withUnsafeMutableBytes { raw in
                            try DCOnlyGreyscaleDecoder.decodeInto(reader: &reader, dcTable: dc, acTable: ac,
                                quantiser: 255, plan: plan, width: sample.width, height: sample.height,
                                precision: precision, restartInterval: 3, floatOutput: floating,
                                destination: .init(bytes: .init(rebasing: raw[offset..<(raw.count - suffix)]),
                                    rowBytes: rowBytes, bytesPerSample: bps))
                        }
                    }
                }
            }
            #expect(polls.withLock { $0 } == stopAt)
            #expect(output.allSatisfy { $0 == 0xA5 })
            // No delayed worker or temporary owner may still hold this borrow.
            // Reuse immediately; sanitised runs can observe any escaped access.
            _ = output.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0xA5) }
            reader = BitReader(data: scan.entropyData)
            try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 8)) {
                try output.withUnsafeMutableBytes { raw in
                    try DCOnlyGreyscaleDecoder.decodeInto(reader: &reader, dcTable: dc, acTable: ac,
                        quantiser: 255, plan: plan, width: sample.width, height: sample.height,
                        precision: precision, restartInterval: 3, floatOutput: floating,
                        destination: .init(bytes: .init(rebasing: raw[offset..<(raw.count - suffix)]),
                            rowBytes: rowBytes, bytesPerSample: bps))
                }
            }
            #expect(output == padded(expected, width: sample.width, height: sample.height,
                bps: bps, offset: offset, rowBytes: rowBytes, suffix: suffix))
        }
    }

    @Test(arguments: [8, 12])
    func publicMalformedEntropyAbortsWithoutSealingOrChangingPixels(precision: Int) async throws {
        for blocks in [16, 17] {
            // One zero byte decodes only a few zero-DC/EOB blocks. Parsing and
            // admission succeed, then entropy ends inside the sole output batch.
            let sample = try fixture(blocks: blocks, precision: precision, replacementEntropy: [0])
            for backend in Decoder.capabilities.availableBackends {
                _ = try admittedPlan(sample, precision: precision, floating: false, backend: backend, blocks: blocks)
                let decoder = try Decoder()
                let descriptor = try decoder.inspect(sample.jpeg).descriptor
                let storage = try TinyDCObservedStorage(byteCount: descriptor.requiredByteCount)
                let destination = try ImageDestination(descriptor: descriptor, storage: storage)
                do {
                    _ = try await decoder.decode(sample.jpeg, into: destination,
                        options: .init(executionPolicy: .required(backend)))
                    Issue.record("Truncated tiny JPEG published an image")
                } catch let error as CodecError { #expect(error.category == .malformedInput) }
                let events = storage.events.withLock { $0 }
                #expect(events.borrows == 1 && events.seals == 0 && events.aborts == 1)
                #expect(events.bytes.count == descriptor.requiredByteCount && events.bytes.allSatisfy { $0 == 0xA5 })
                #expect(throws: CodecError.self) { _ = try storage.reserveWrite() }
            }
        }
    }
}
