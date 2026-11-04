// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Raster Images Private Limited

/// Fixed scalar failure facts. Formatting and throwing belong outside qualified work.
public struct QualifiedFailure: Sendable, Equatable {
    /// Stable category; the first four raw values preserve the pinned predecessor.
    public enum Kind: UInt8, Sendable { case cancelled, invalidJPEG, decoding, unsupported, resourceLimit }
    public let code: UInt16
    public let kind: Kind
    public let detail0: Int, detail1: Int, detail2: Int
    internal init(code: UInt16, kind: Kind, detail0: Int = 0, detail1: Int = 0, detail2: Int = 0) {
        self.code = code; self.kind = kind
        self.detail0 = detail0; self.detail1 = detail1; self.detail2 = detail2
    }
}

/// Nonthrowing transport. No error existential, message or owning output is constructed.
public enum QualifiedOutcome<Value> {
    case success(Value)
    case failure(QualifiedFailure)
    internal var failureValue: QualifiedFailure {
        switch self {
        case .failure(let value): return value
        case .success: preconditionFailure("Internal failure extraction requires failure")
        }
    }
}
extension QualifiedOutcome: Sendable where Value: Sendable {}

/// Unsafe synchronous cancellation borrow; deliberately not Sendable. The caller
/// retains the context until return and synchronises any concurrent flag writes.
/// The callback must not mutate input or access output/workspace; its own work and
/// allocations remain the caller's responsibility. No callback runs after return.
public struct QualifiedCancellation {
    public typealias Check = @convention(c) (UnsafeRawPointer?) -> Bool
    private let context: UnsafeRawPointer?
    private let isCancelled: Check?
    private var deadline: UInt64 = 0
    public init(context: UnsafeRawPointer? = nil, isCancelled: Check? = nil) {
        self.context = context; self.isCancelled = isCancelled
    }
    public static var never: Self { .init() }
    internal func startingDeadline(seconds: Double) -> QualifiedOutcome<Self> {
        guard seconds.isFinite, seconds > 0, let now = qualifiedClock() else {
            return .failure(.init(code: 170, kind: .resourceLimit))
        }
        let scaled = seconds * 1_000_000_000
        let duration = scaled >= Double(UInt64.max) ? UInt64.max : max(1, UInt64(scaled))
        let end = now.addingReportingOverflow(duration)
        var value = self; value.deadline = end.overflow ? UInt64.max : end.partialValue
        return .success(value)
    }
    internal func check() -> QualifiedOutcome<Void> {
        if isCancelled?(context) == true { return .failure(.init(code: 1, kind: .cancelled)) }
        if deadline != 0 {
            guard let now = qualifiedClock(), now < deadline else {
                return .failure(.init(code: 171, kind: .resourceLimit))
            }
        }
        return .success(())
    }
}
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
private func qualifiedClock() -> UInt64? {
    var value = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &value) == 0, value.tv_sec >= 0, value.tv_nsec >= 0 else { return nil }
    let seconds = UInt64(value.tv_sec).multipliedReportingOverflow(by: 1_000_000_000)
    let nanos = seconds.partialValue.addingReportingOverflow(UInt64(value.tv_nsec))
    return seconds.overflow || nanos.overflow ? nil : nanos.partialValue
}
