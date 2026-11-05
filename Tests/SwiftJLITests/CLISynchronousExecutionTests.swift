// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

private final class SynchronousPollState: Sendable {
    let events = Mutex<[String]>([])
    let releases = Mutex(0)
}

private final class SynchronousPollLifetime: Sendable {
    let name: String
    let state: SynchronousPollState
    init(name: String, state: SynchronousPollState) {
        self.name = name; self.state = state
    }
    func poll() { state.events.withLock { $0.append(name) } }
    deinit { state.releases.withLock { $0 += 1 } }
}

@Suite struct CLISynchronousExecutionTests {
    @Test func nestedHostCancellationRestoresOuterPollAndReleasesCapturesAfterThrow() throws {
        enum Probe: Error { case stop }
        let state = SynchronousPollState()
        func invokeScopes() throws -> Int {
            let outer = SynchronousPollLifetime(name: "outer", state: state)
            return try NativeOperation.withSynchronousCancellation({ outer.poll() }) {
                try NativeOperation.$current.withValue(.init(seconds: 120)) {
                    try NativeOperation.check()
                    do {
                        let inner = SynchronousPollLifetime(name: "inner", state: state)
                        try NativeOperation.withSynchronousCancellation({ inner.poll() }) {
                            try NativeOperation.$current.withValue(.init(seconds: 120)) {
                                try NativeOperation.check()
                                throw Probe.stop
                            }
                        }
                    } catch Probe.stop {}
                    // The existing outer operation and a newly captured operation
                    // must both recover the outer callback after the inner throw.
                    try NativeOperation.check()
                    try NativeOperation.$current.withValue(.init(seconds: 120)) {
                        try NativeOperation.check()
                    }
                    return 42
                }
            }
        }
        #expect(try invokeScopes() == 42)
        #expect(state.events.withLock { $0 } == ["outer", "outer", "inner", "inner", "outer", "outer", "outer"])
        #expect(state.releases.withLock { $0 } == 2)
        // No callback may remain attached to an operation created after the scope.
        try NativeOperation.$current.withValue(.init(seconds: 120)) { try NativeOperation.check() }
        #expect(state.events.withLock { $0.count } == 7)
    }

    @Test(arguments: [false, true])
    func hostAdaptersPreserveBytesAndReports(lossy: Bool) async throws {
        let descriptor = try ImageDescriptor.greyscale16(width: 67, height: 33, meaningfulBits: 12)
        let image = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { x, y in
            UInt16((x * 193 + y * 71) & 4095)
        }
        let encoder = try Encoder(configuration: .init(mode: lossy ? .lossy : .lossless))
        let asyncEncoded = try await encoder.encode(image)
        let syncEncoded = try encoder.encodeSynchronously(image, cancellationCheck: {})
        #expect(syncEncoded.data == asyncEncoded.data)
        #expect(syncEncoded.report.fidelity == asyncEncoded.report.fidelity)
        let decoder = try Decoder()
        let asynchronous = try await decoder.decode(syncEncoded.data)
        let synchronous = try decoder.decodeSynchronously(syncEncoded.data, cancellationCheck: {})
        #expect(try synchronous.image.storage.withUnsafeBytes { Array($0) }
            == asynchronous.image.storage.withUnsafeBytes { Array($0) })
        #expect(synchronous.report.fidelity == asynchronous.report.fidelity)
        #expect(synchronous.report.backend == asynchronous.report.backend)
        #expect(synchronous.report.copyEvents == asynchronous.report.copyEvents)
        #expect(try decoder.inspectJPEGSynchronously(syncEncoded.data, cancellationCheck: {}).width == 67)
    }

    @Test func hostCancellationReachesJoinedWorkersWithoutASwiftTask() throws {
        let state = Mutex((cancel: false, active: 0, entered: 0, polls: 0,
                           noTask: false, cancelled: false))
        let entered = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { finished.signal() }
            state.withLock { $0.noTask = withUnsafeCurrentTask { $0 == nil } }
            do {
                try NativeOperation.withSynchronousCancellation({
                    let cancelled = state.withLock { $0.polls += 1; return $0.cancel }
                    if cancelled { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 5, maximumWorkers: 2)) {
                        try NativeOperation.perform(iterations: 2) { _ in
                            state.withLock { $0.active += 1; $0.entered += 1 }
                            defer { state.withLock { $0.active -= 1 } }
                            entered.signal()
                            while true { try NativeOperation.check(); Thread.sleep(forTimeInterval: 0.001) }
                        }
                    }
                }
            } catch is CancellationError { state.withLock { $0.cancelled = true } }
            catch { Issue.record("Unexpected synchronous host error: \(error)") }
        }
        thread.start()
        #expect(entered.wait(timeout: .now() + 3) == .success)
        state.withLock { $0.cancel = true }
        #expect(finished.wait(timeout: .now() + 6) == .success)
        let observed = state.withLock { $0 }
        #expect(observed.noTask && observed.cancelled && observed.entered > 0)
        #expect(observed.active == 0 && observed.polls > 1)
        // A completed throwing scope must not leak its callback to later work.
        try NativeOperation.$current.withValue(.init(seconds: 5)) { try NativeOperation.check() }
    }

    @Test func nestedHostScopeRetainsTaskCancellationForJoinedWorkers() async throws {
        let entered = DispatchSemaphore(value: 0)
        let state = Mutex((active: 0, started: 0, noTask: false))
        let task = Task.detached {
            defer { entered.signal() }
            try await NativeOperation.withCancellation {
                try NativeOperation.withSynchronousCancellation({}) {
                    let context = NativeOperation(seconds: 5, maximumWorkers: 2)
                    let finished = DispatchSemaphore(value: 0)
                    let result = Mutex<Result<Void, any Error>?>(nil)
                    // Every worker runs outside a Swift task, so Task.checkCancellation
                    // cannot conceal a lost inherited cancellation token.
                    let host = Thread {
                        let outcome = Result {
                            try NativeOperation.$current.withValue(context) {
                                try NativeOperation.perform(iterations: 2) { _ in
                                    let noTask = withUnsafeCurrentTask { $0 == nil }
                                    state.withLock { $0.active += 1; $0.started += 1; $0.noTask = $0.noTask || noTask }
                                    defer { state.withLock { $0.active -= 1 } }
                                    entered.signal()
                                    while true { try NativeOperation.check(); Thread.sleep(forTimeInterval: 0.001) }
                                }
                            }
                        }
                        result.withLock { $0 = outcome }
                        finished.signal()
                    }
                    host.start()
                    try #require(finished.wait(timeout: .now() + 6) == .success)
                    let outcome = try #require(result.withLock { $0 })
                    try outcome.get()
                }
            }
        }
        // A dedicated thread avoids depending on a free cooperative-executor lane
        // while the synchronous host waits for its explicitly joined workers.
        let canceller = Thread { entered.wait(); task.cancel() }
        canceller.qualityOfService = .userInitiated
        canceller.start()
        await #expect(throws: CancellationError.self) { try await task.value }
        let observed = state.withLock { $0 }
        #expect(observed.started > 0 && observed.noTask && observed.active == 0)
    }

    @Test func hostDeadlineAndMalformedCategoriesRemainDistinct() throws {
        let decoder = try Decoder()
        #expect(throws: CancellationError.self) {
            try decoder.decodeSynchronously(Data(), cancellationCheck: { throw CancellationError() })
        }
        for expired in [false, true] {
            do {
                _ = try decoder.decodeSynchronously(Data(), cancellationCheck: {
                    if expired { throw CodecError(.resourceLimitExceeded, "Host deadline") }
                })
                Issue.record("Invalid input unexpectedly accepted")
            } catch let error as CodecError {
                #expect(error.category == (expired ? .resourceLimitExceeded : .malformedInput))
            }
        }
    }
}
