// SPDX-License-Identifier: Apache-2.0
import Foundation

/// An immutable compressed-input owner with indices relative to this view.
/// Data slices retain their allocation; scan extraction does not duplicate the
/// entropy payload. Raw borrows end with each synchronous buffer access.
struct JPEGBytes: RandomAccessCollection, Sendable, Equatable {
    typealias Index = Int
    private let storage: Data

    init(_ storage: Data) { self.storage = storage }
    init(_ bytes: [UInt8]) { self.storage = Data(bytes) }

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }
    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try storage.withUnsafeBytes(body)
    }

    subscript(index: Int) -> UInt8 { storage[storage.startIndex + index] }
    func rebasedSlice(_ bounds: Range<Int>) -> JPEGBytes {
        JPEGBytes(storage[(storage.startIndex + bounds.lowerBound)..<(storage.startIndex + bounds.upperBound)])
    }
}
