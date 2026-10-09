// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

@Suite struct NativeExecutionTests {
    @Test(arguments: [1, 2, 4])
    func joinedWorkersRespectLimitAndBackend(limit: Int) throws {
        let state = Mutex((active: 0, peak: 0, finished: 0, wrongBackend: false))
        try NativeOperation.$current.withValue(.init(seconds: 10, backend: .accelerated, maximumWorkers: limit)) {
            try NativeOperation.perform(iterations: 17) { _ in
                state.withLock {
                    $0.active += 1; $0.peak = max($0.peak, $0.active)
                    $0.wrongBackend = $0.wrongBackend || NativeOperation.current?.backend != .accelerated
                }
                defer { state.withLock { $0.active -= 1; $0.finished += 1 } }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        let observed = state.withLock { $0 }
        #expect(observed.active == 0 && observed.finished == 17 && !observed.wrongBackend)
        #expect(observed.peak >= 1 && observed.peak <= limit)
    }

    @Test func failureJoinsEveryStartedWorker() throws {
        let active = Mutex(0)
        do {
            try NativeOperation.$current.withValue(.init(seconds: 10, maximumWorkers: 4)) {
                try NativeOperation.perform(iterations: 16) { i in
                    active.withLock { $0 += 1 }
                    defer { active.withLock { $0 -= 1 } }
                    Thread.sleep(forTimeInterval: i == 0 ? 0.001 : 0.01)
                    if i == 0 { throw CodecError(.invalidArgument, "Injected worker failure") }
                }
            }
            Issue.record("Worker failure was lost")
        } catch let error as CodecError { #expect(error.category == .invalidArgument) }
        #expect(active.withLock { $0 } == 0)
    }

    @Test(arguments: [10.0, Double.greatestFiniteMagnitude])
    func cancellationReachesDispatchWorkersAndJoins(seconds: Double) async throws {
        let entered = DispatchSemaphore(value: 0)
        let state = Mutex((active: 0, started: 0))
        let lanes = min(2, ProcessInfo.processInfo.activeProcessorCount)
        let task = Task.detached {
            // Also unblock the cancellation thread if setup fails before a worker
            // starts; the started assertion and expected error expose that failure.
            defer { entered.signal() }
            try await NativeOperation.withCancellation {
                try NativeOperation.$current.withValue(.init(seconds: seconds, maximumWorkers: lanes)) {
                    try NativeOperation.perform(iterations: lanes) { _ in
                        state.withLock { $0.active += 1; $0.started += 1 }
                        defer { state.withLock { $0.active -= 1 } }
                        entered.signal()
                        while true { try NativeOperation.check(); Thread.sleep(forTimeInterval: 0.001) }
                    }
                }
            }
        }
        // Cancellation must not wait for a saturated cooperative executor to
        // resume this test. The dedicated thread cancels only after real work
        // starts; there is no assumption about task startup latency or lane order.
        let canceller = Thread { entered.wait(); task.cancel() }
        canceller.qualityOfService = .userInitiated
        canceller.start()
        await #expect(throws: CancellationError.self) { try await task.value }
        let observed = state.withLock { $0 }
        #expect(observed.started > 0 && observed.active == 0)
    }

    @Test func deadlineReachesJoinedWorkers() throws {
        do {
            try NativeOperation.$current.withValue(.init(seconds: 0.000001, maximumWorkers: 2)) {
                try NativeOperation.perform(iterations: 8) { _ in try NativeOperation.check() }
            }
            Issue.record("Worker deadline was ignored")
        } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
    }

    @Test(arguments: [120.0, 1e100, Double.greatestFiniteMagnitude])
    func finiteDeadlinesDoNotTrap(seconds: Double) async throws {
        let limits = try ResourceLimits(deadlineSeconds: seconds)
        let decoder = try Decoder()
        // Invalid input must still return its defined error, even with a
        // deadline too large to construct as a Duration.
        do {
            _ = try decoder.inspect(Data(), options: .init(resourceLimits: limits))
            Issue.record("Empty JPEG accepted")
        } catch let error as CodecError { #expect(error.category == .malformedInput) }

        let descriptor = try ImageDescriptor.greyscale16(width: 2, height: 2)
        let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { x, y in
            UInt16(x + y * 2)
        }
        let encoded = try await Encoder().encode(image, options: .init(resourceLimits: limits))
        #expect(try decoder.inspectJPEG(encoded.data, options: .init(resourceLimits: limits)).width == 2)
        let allocated = try await decoder.decode(encoded.data, options: .init(resourceLimits: limits))
        let destination = try ImageDestination.allocate(descriptor: descriptor)
        let supplied = try await decoder.decode(encoded.data, into: destination,
            options: .init(resourceLimits: limits))
        for y in 0..<2 { for x in 0..<2 {
            #expect(try allocated.image.sampleUInt16(x: x, y: y) == image.sampleUInt16(x: x, y: y))
            #expect(try supplied.image.sampleUInt16(x: x, y: y) == image.sampleUInt16(x: x, y: y))
        } }
    }

    @Test func fractionalDeadlineStillExpires() throws {
        let started = ContinuousClock.now.advanced(by: .seconds(-2))
        do {
            try NativeOperation.$current.withValue(.init(seconds: 1.5, started: started)) {
                try NativeOperation.check()
            }
            Issue.record("Elapsed deadline was ignored")
        } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
    }

    @Test(arguments: [false, true])
    func publicPredictiveParallelismPreservesBytes(restarts: Bool) async throws {
        let width = 257, height = 513
        let descriptor = try ImageDescriptor.greyscale16(width: width, height: height, rowBytes: 520, offset: 4)
        let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { x, y in
            UInt16(truncatingIfNeeded: x * 193 + y * 31957)
        }
        let encoder = try Encoder(configuration: .init(codecOptions: .init(predictor: 7,
            restartInterval: restarts ? width * 2 : 0)))
        let serial = try await encoder.encode(image, options: .init(resourceLimits: .init(maximumWorkers: 1)))
        let parallel = try await encoder.encode(image, options: .init(resourceLimits: .init(maximumWorkers: 2)))
        #expect(serial.data == parallel.data)
        #expect(parallel.report.copyEvents.isEmpty && parallel.report.pixelAllocationCount == 0)
        let decoded = try await Decoder().decode(parallel.data)
        for y in 0..<height { for x in 0..<width {
            #expect(try decoded.image.sampleUInt16(x: x, y: y) == image.sampleUInt16(x: x, y: y))
        } }
    }
    @Test(arguments: [false, true])
    func publicDCTWorkerCountsPreserveBackendAndBytes(progressive: Bool) async throws {
        let width = 513, height = 257, row = width * 3
        let plane = try PlaneDescriptor(width: width, height: height, components: [0, 1, 2],
            sampleStride: 1, pixelStride: 3, rowBytes: row, byteCount: row * height)
        let descriptor = try ImageDescriptor(width: width, height: height, storageBits: 8, meaningfulBits: 8,
            components: [.red, .green, .blue], colour: .rgb, planes: [plane])
        let image = try ImageDestination.allocate(descriptor: descriptor).write { bytes in
            for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i * 73 + i / row) }
        }
        let encoder = try Encoder(configuration: .init(mode: .lossy, codecOptions: .init(dct:
            .init(progressiveMode: progressive ? .successiveApproximation : .sequential))))
        for backend in Encoder.capabilities.availableBackends {
            let one = try ResourceLimits(maximumWorkers: 1), two = try ResourceLimits(maximumWorkers: 2)
            let serial = try await encoder.encode(image, options: .init(resourceLimits: one, executionPolicy: .required(backend)))
            let parallel = try await encoder.encode(image, options: .init(resourceLimits: two, executionPolicy: .required(backend)))
            #expect(serial.data == parallel.data && parallel.report.backend == backend)
            let a = try await Decoder().decode(serial.data, options: .init(resourceLimits: one, executionPolicy: .required(backend)))
            let b = try await Decoder().decode(serial.data, options: .init(resourceLimits: two, executionPolicy: .required(backend)))
            #expect(try a.image.storage.withUnsafeBytes { Array($0) } == b.image.storage.withUnsafeBytes { Array($0) })
            #expect(b.report.backend == backend)
        }
    }

}
