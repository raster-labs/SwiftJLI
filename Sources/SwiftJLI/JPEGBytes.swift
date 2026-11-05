// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(ObjectiveC)
import CoreFoundation
#endif

/// Immutable bridge owner shared by parsed scans and joined decode workers.
///
/// Sendability proof: construction accepts a Data value and bridges its immutable
/// snapshot once. The NSData is private to this file, never cast to mutable data
/// or exposed for mutation. Data copy-on-write preserves that snapshot when the
/// caller changes its own value. Workers share only read-only ranges of this
/// owner; cached pointers exist only in local non-Sendable BitReaders and the
/// synchronous MarkerReader. Neither reader is stored in a parsed result.
/// Each load explicitly keeps the owner alive. Ownership/COW/release and joined
/// reader tests exercise this boundary; no unchecked annotation covers a pointer.
/// On Objective-C platforms, the toll-free Core Foundation getter avoids the
/// NSData.bytes inner-pointer autorelease. Ordinary decode scopes therefore
/// release the input without an enclosing autorelease pool.
private final class JPEGByteOwner: @unchecked Sendable {
    let data: NSData
    init(_ data: Data) { self.data = data as NSData }
}

/// An immutable compressed-input owner with indices relative to this view.
/// All scan ranges retain one immutable Foundation owner. Bridging Data retains
/// its value semantics; no pointer is obtained from an escaped Data borrow.
struct JPEGBytes: RandomAccessCollection, Sendable, Equatable {
    typealias Index = Int
    private let storage: JPEGByteOwner
    private let bounds: Range<Int>

    init(_ data: Data) {
        self.storage = JPEGByteOwner(data)
        self.bounds = 0..<data.count
    }
    init(_ bytes: [UInt8]) { self.init(Data(bytes)) }
    private init(storage: JPEGByteOwner, bounds: Range<Int>) {
        self.storage = storage
        self.bounds = bounds
    }

    var startIndex: Int { 0 }
    var endIndex: Int { bounds.count }

    /// NSData documents bytes as valid until immutable owner deallocation.
    /// Only synchronous, non-Sendable bit and marker readers cache this view. Their loads
    /// explicitly extend this owner's lifetime; this is not a Data buffer borrow.
    var ownedBuffer: UnsafeRawBufferPointer {
        guard !bounds.isEmpty else { return .init(start: nil, count: 0) }
        return withExtendedLifetime(storage) {
            #if canImport(ObjectiveC)
            // NSData.bytes is NS_RETURNS_INNER_POINTER, which adds a temporary
            // owner autorelease. This ordinary toll-free cast and C getter
            // access the same immutable allocation without that delayed retain.
            // The actual owner stays alive here and in every cached reader load.
            let data = storage.data as CFData
            let bytes = UnsafeRawBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data))
            #else
            // No Objective-C autorelease semantics exist on this path.
            let bytes = UnsafeRawBufferPointer(start: storage.data.bytes, count: storage.data.length)
            #endif
            return UnsafeRawBufferPointer(rebasing: bytes[bounds])
        }
    }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try withExtendedLifetime(storage) { try body(ownedBuffer) }
    }

    subscript(index: Int) -> UInt8 {
        withUnsafeBytes { $0[index] }
    }
    func rebasedSlice(_ bounds: Range<Int>) -> JPEGBytes {
        precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count)
        return JPEGBytes(storage: storage,
            bounds: (self.bounds.lowerBound + bounds.lowerBound)..<(self.bounds.lowerBound + bounds.upperBound))
    }

    static func == (lhs: JPEGBytes, rhs: JPEGBytes) -> Bool {
        lhs.elementsEqual(rhs)
    }
}
