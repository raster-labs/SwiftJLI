// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import SwiftJLI
import Testing

// Separate from the shipping graph. Serial execution keeps resource observations
// attributable to one case. Desktop/simulator execution is harness validation only.
@Suite(.serialized) struct WatchQualificationTests {
    private let limits = ResourceLimits.watch

    private func fixture(width: Int = 129, height: Int = 127, bits: Int = 16) throws -> Image {
        let descriptor = try ImageDescriptor.greyscale16(width: width, height: height,
            meaningfulBits: bits, rowBytes: width * 2 + 8, offset: 4, limits: limits)
        return try ImageDestination.allocate(descriptor: descriptor, limits: limits).writeUInt16 { x, y in
            UInt16((x * 193 + y * 31957) & ((1 << bits) - 1))
        }
    }

    private func checkSamples(_ image: Image, bits: Int) throws {
        let d = image.descriptor
        try #require(d.meaningfulBits == bits && d.storageBits == 16)
        try #require(d.sampleType == .unsignedInteger && d.components == [.grey])
        // Independent deterministic expectations for the synthetic ramp.
        for y in 0..<d.height { for x in 0..<d.width {
            try #require(image.sampleUInt16(x: x, y: y) == UInt16((x * 193 + y * 31957) & ((1 << bits) - 1)))
        } }
        try image.storage.withUnsafeBytes { raw in
            let p = d.planes[0]
            try #require(raw[..<p.offset].allSatisfy({ $0 == 0 }) == true)
            for y in 0..<d.height {
                let start = p.offset + y * p.rowBytes + d.width * 2
                try #require(raw[start..<(p.offset + (y + 1) * p.rowBytes)].allSatisfy({ $0 == 0 }) == true)
            }
        }
    }

    private func record(_ name: String, started: ContinuousClock.Instant, extra: [String: Any] = [:]) throws {
        let duration = started.duration(to: .now).components
        var usage = rusage()
        try #require(getrusage(RUSAGE_SELF, &usage) == 0)
        let environment: String
        #if os(watchOS) && !targetEnvironment(simulator)
        environment = "physical-watch"
        #elseif os(watchOS)
        environment = "watch-simulator"
        #else
        environment = "host-harness-check"
        #endif
        var fields: [String: Any] = ["case": name, "environment": environment,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "elapsedSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
            "processPeakRSSBytes": usage.ru_maxrss,
            "maximumCompressedBytes": limits.maximumCompressedBytes,
            "maximumDecodedBytes": limits.maximumDecodedBytes,
            "maximumWorkspaceBytes": limits.maximumWorkspaceBytes,
            "maximumMemoryBytes": limits.maximumMemoryBytes,
            "maximumWorkers": limits.maximumWorkers, "deadlineSeconds": limits.deadlineSeconds]
        fields.merge(extra) { _, new in new }
        print("WATCH_QUALIFICATION " + String(decoding:
            try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys), as: UTF8.self))
    }

    @Test func profileAndDescriptorBoundary() throws {
        let start = ContinuousClock.now
        #expect(limits.maximumCompressedBytes == 16 * 1024 * 1024)
        #expect(limits.maximumDecodedBytes == 32 * 1024 * 1024)
        #expect(limits.maximumWorkspaceBytes == 32 * 1024 * 1024)
        #expect(limits.maximumMemoryBytes == 64 * 1024 * 1024)
        #expect(limits.maximumWorkers == 2 && limits.deadlineSeconds == 30)
        #if os(watchOS)
        #expect(ResourceLimits.default == limits)
        #endif
        // Descriptor-only probes; no allocation near the device memory ceiling.
        for height in [4095, 4096] {
            _ = try ImageDescriptor.greyscale16(width: 4096, height: height, limits: limits)
        }
        #expect(throws: CodecError.self) {
            try ImageDescriptor.greyscale16(width: 4096, height: 4097, limits: limits)
        }
        try record("profile-and-decoded-boundary", started: start)
    }

    @Test func repeatedLosslessCallerStorage() async throws {
        let start = ContinuousClock.now
        let encoder = try SwiftJLI.Encoder(), decoder = try SwiftJLI.Decoder()
        for bits in [12, 16] {
            let source = try fixture(bits: bits)
            let reference = try await encoder.encode(source, options: .init(resourceLimits: limits))
            for _ in 0..<8 {
                let encoded = try await encoder.encode(source, options: .init(resourceLimits: limits))
                try #require(encoded.data == reference.data)
                try #require(encoded.report.copyEvents.isEmpty && encoded.report.pixelAllocationCount == 0)
                let destination = try ImageDestination.allocate(descriptor: source.descriptor, limits: limits)
                let identity = destination.storage.allocationID
                let decoded = try await decoder.decode(encoded.data, into: destination,
                    options: .init(resourceLimits: limits))
                try #require(decoded.image.storage.allocationID == identity)
                try #require(decoded.report.copyEvents.isEmpty && decoded.report.pixelAllocationCount == 0)
                try checkSamples(decoded.image, bits: bits)
                #expect(throws: CodecError.self) { try destination.writeUInt16 { _, _ in 0 } }
            }
        }
        try record("repeated-lossless-caller-storage", started: start, extra: ["roundTrips": 16])
    }

    @Test func boundedConcurrentReaders() async throws {
        let start = ContinuousClock.now
        let source = try fixture()
        let encoder = try SwiftJLI.Encoder()
        let reference = try await encoder.encode(source, options: .init(resourceLimits: limits))
        // Two small frames, each with the Watch worker cap; both tasks are joined.
        // This is not a claim of process-wide admission for arbitrary concurrency.
        for _ in 0..<4 {
            async let a = encoder.encode(source, options: .init(resourceLimits: limits))
            async let b = encoder.encode(source, options: .init(resourceLimits: limits))
            let results = try await (a, b)
            try #require(results.0.data == reference.data && results.1.data == reference.data)
        }
        try record("concurrent-readers", started: start, extra: ["encodes": 8, "maximumInFlight": 2])
    }

    @Test func dctProfilesUnderWatchBudgets() async throws {
        let start = ContinuousClock.now
        var cases = 0
        for bits in [8, 12] {
            for components in [1, 3] {
                let bytes = bits == 8 ? 1 : 2, width = 65, height = 63
                let row = width * components * bytes + 8
                let plane = try PlaneDescriptor(width: width, height: height,
                    components: Array(0..<components), offset: 4, sampleStride: bytes,
                    pixelStride: components * bytes, rowBytes: row, byteCount: 4 + row * height)
                let descriptor = try ImageDescriptor(width: width, height: height,
                    storageBits: bytes * 8, meaningfulBits: bits,
                    components: components == 1 ? [.grey] : [.red, .green, .blue],
                    colour: components == 1 ? .greyscale : .rgb, planes: [plane], limits: limits)
                let source = try ImageDestination.allocate(descriptor: descriptor, limits: limits).write { raw in
                    for y in 0..<height { for x in 0..<(width * components) {
                        let sample = (x * 101 + y * 193) & ((1 << bits) - 1)
                        let offset = 4 + y * row + x * bytes
                        raw[offset] = UInt8(truncatingIfNeeded: sample)
                        if bytes == 2 { raw[offset + 1] = UInt8(sample >> 8) }
                    } }
                }
                for progressive in [false, true] {
                    let encoder = try SwiftJLI.Encoder(configuration: .init(mode: .lossy,
                        codecOptions: .init(dct: .init(progressiveMode:
                            progressive ? .successiveApproximation : .sequential))))
                    for backend in SwiftJLI.Encoder.capabilities.availableBackends {
                        let encoded = try await encoder.encode(source, options: .init(
                            resourceLimits: limits, executionPolicy: .required(backend)))
                        let decoder = try SwiftJLI.Decoder()
                        let info = try decoder.inspectJPEG(encoded.data, options: .init(resourceLimits: limits))
                        try #require(info.bitsPerComponent == bits)
                        let destination = try ImageDestination.allocate(descriptor: descriptor, limits: limits)
                        let decoded = try await decoder.decode(encoded.data, into: destination,
                            options: .init(resourceLimits: limits, executionPolicy: .required(backend)))
                        try #require(decoded.image.storage.allocationID == destination.storage.allocationID)
                        try #require(decoded.report.backend == backend && encoded.report.backend == backend)
                        try #require(decoded.report.copyEvents.isEmpty && decoded.report.pixelAllocationCount == 0)
                        try #require(decoded.image.descriptor.meaningfulBits == bits)
                        cases += 1
                    }
                }
            }
        }
        try record("dct-watch-budgets", started: start, extra: ["profiles": cases])
    }

    @Test func defaultWorkspaceAdmissionAndRecovery() async throws {
        let start = ContinuousClock.now
        // The input fits decoded storage, but the encoder's conservative workspace
        // reservation exceeds 32 MiB. Denial must occur before codec work starts.
        let tooLarge = try fixture(width: 1024, height: 513)
        let encoder = try SwiftJLI.Encoder()
        do {
            _ = try await encoder.encode(tooLarge, options: .init(resourceLimits: limits))
            Issue.record("Watch workspace admission incorrectly succeeded")
        } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        let small = try fixture()
        let encoded = try await encoder.encode(small, options: .init(resourceLimits: limits))
        let result = try await SwiftJLI.Decoder().decode(encoded.data, options: .init(resourceLimits: limits))
        try checkSamples(result.image, bits: 16)
        try record("workspace-denial-and-recovery", started: start)
    }

    @Test func cancellationAndDeadlineRecovery() async throws {
        let start = ContinuousClock.now
        let source = try fixture()
        let encoder = try SwiftJLI.Encoder(), decoder = try SwiftJLI.Decoder()
        let encoded = try await encoder.encode(source, options: .init(resourceLimits: limits))
        let cancel: @Sendable (ProgressUpdate) -> Void = { update in
            if update.phase == .processing { withUnsafeCurrentTask { $0?.cancel() } }
        }
        for _ in 0..<4 {
            let encodeTask = Task { try await encoder.encode(source,
                options: .init(resourceLimits: limits, progress: cancel)) }
            await #expect(throws: CancellationError.self) { try await encodeTask.value }
            let destination = try ImageDestination.allocate(descriptor: source.descriptor, limits: limits)
            let decodeTask = Task { try await decoder.decode(encoded.data, into: destination,
                options: .init(resourceLimits: limits, progress: cancel)) }
            await #expect(throws: CancellationError.self) { try await decodeTask.value }
        }
        // Only the deadline is lowered; every other ceiling remains Watch-sized.
        let short = try ResourceLimits(maximumCompressedBytes: limits.maximumCompressedBytes,
            maximumDecodedBytes: limits.maximumDecodedBytes, maximumWorkspaceBytes: limits.maximumWorkspaceBytes,
            maximumPixels: limits.maximumPixels, maximumDimension: limits.maximumDimension,
            maximumFrames: limits.maximumFrames, maximumMetadataBytes: limits.maximumMetadataBytes,
            maximumICCBytes: limits.maximumICCBytes, maximumNestingDepth: limits.maximumNestingDepth,
            maximumWorkers: limits.maximumWorkers, deadlineSeconds: 0.000001,
            maximumMemoryBytes: limits.maximumMemoryBytes)
        for decode in [false, true] {
            do {
                if decode { _ = try await decoder.decode(encoded.data, options: .init(resourceLimits: short)) }
                else { _ = try await encoder.encode(source, options: .init(resourceLimits: short)) }
                Issue.record("Expired deadline incorrectly published a result")
            } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
        }
        let recovered = try await decoder.decode(encoded.data, options: .init(resourceLimits: limits))
        try checkSamples(recovered.image, bits: 16)
        try record("cancellation-deadline-recovery", started: start,
            extra: ["cancelledOperations": 8, "expiredOperations": 2])
    }
}
