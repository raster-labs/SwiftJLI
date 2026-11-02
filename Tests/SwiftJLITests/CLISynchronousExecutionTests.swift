// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

@Suite struct CLISynchronousExecutionTests {
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
