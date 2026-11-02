// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization

/// A cancellation handler may run concurrently with synchronous codec workers.
/// The mutex owns the only mutable state; no task handle or storage pointer escapes.
final class NativeCancellation: Sendable {
    private let state = Mutex(false)
    func cancel() { state.withLock { $0 = true } }
    func check() throws {
        if state.withLock({ $0 }) { throw CancellationError() }
    }
}

/// Context is explicitly installed in every joined worker. A worker never relies
/// on inheriting Swift task locals or cancellation through a Dispatch thread.
struct NativeOperation: Sendable {
    @TaskLocal static var current: NativeOperation?
    @TaskLocal private static var taskCancellation: NativeCancellation?
    @TaskLocal private static var callerCancellationCheck: (@Sendable () throws -> Void)?
    let started: ContinuousClock.Instant
    let seconds: Double
    let backend: Backend
    let maximumWorkers: Int
    let cancellation: NativeCancellation?
    private let synchronousCancellationCheck: (@Sendable () throws -> Void)?

    init(seconds: Double, backend: Backend = .scalarCPU,
         started: ContinuousClock.Instant = .now, maximumWorkers: Int = 1) {
        self.seconds = seconds; self.backend = backend; self.started = started
        self.maximumWorkers = max(1, maximumWorkers)
        self.cancellation = Self.taskCancellation
        self.synchronousCancellationCheck = Self.callerCancellationCheck
    }

    static func withCancellation<T: Sendable>(_ body: () throws -> T) async throws -> T {
        let token = NativeCancellation()
        return try await withTaskCancellationHandler {
            try $taskCancellation.withValue(token) { try body() }
        } onCancel: { token.cancel() }
    }

    /// The executable has a blocking caller-thread executor and a signal/deadline
    /// poll. Capture that poll in every operation context so joined Dispatch
    /// workers inherit it explicitly, just like asynchronous cancellation tokens.
    /// The callback must be thread-safe and non-blocking. No work outlives body.
    static func withSynchronousCancellation<T>(
        _ check: @escaping @Sendable () throws -> Void, _ body: () throws -> T
    ) throws -> T {
        try $callerCancellationCheck.withValue(check) {
            try check()
            let result = try body()
            try check()
            return result
        }
    }

    static func check() throws {
        try Task.checkCancellation()
        if let context = current {
            try context.cancellation?.check()
            try context.synchronousCancellationCheck?()
            // ResourceLimits accepts every positive finite Double. Converting
            // that caller value to Duration can trap outside Duration's range.
            // Elapsed components always fit in Double, so compare in seconds.
            let elapsed = context.started.duration(to: .now).components
            let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            if elapsedSeconds >= context.seconds {
                throw CodecError(.resourceLimitExceeded, "JPEG operation deadline exceeded.")
            }
        }
    }

    static var workerLimit: Int {
        max(1, min(current?.maximumWorkers ?? ProcessInfo.processInfo.activeProcessorCount,
                   ProcessInfo.processInfo.activeProcessorCount))
    }

    /// Each lane processes disjoint indices. concurrentPerform joins every lane
    /// before returning or throwing, including cancellation/failure. Callers retain
    /// owners and scoped pointer borrows through this entire synchronous call.
    /// The lane count, rather than the number of work items, obeys the worker cap.
    static func perform(iterations: Int, _ body: @Sendable (Int) throws -> Void) throws {
        guard iterations > 0 else { return }
        let lanes = min(iterations, workerLimit)
        if lanes == 1 {
            for i in 0..<iterations { try check(); try body(i) }
            try check()
            return
        }
        let context = current
        let failure = Mutex<(any Error)?>(nil)
        DispatchQueue.concurrentPerform(iterations: lanes) { lane in
            do {
                try $current.withValue(context) {
                    for i in stride(from: lane, to: iterations, by: lanes) {
                        if failure.withLock({ $0 != nil }) { return }
                        try check()
                        try body(i)
                    }
                    try check()
                }
            } catch {
                failure.withLock { if $0 == nil { $0 = error } }
            }
        }
        if let error = failure.withLock({ $0 }) { throw error }
        try check()
    }
}
