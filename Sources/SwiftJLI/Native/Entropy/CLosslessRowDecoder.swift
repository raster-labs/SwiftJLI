// SPDX-License-Identifier: MIT
import SwiftJLIEntropyC

/// Scan-local, non-Sendable metadata borrowed by synchronous caller-thread row
/// calls only. The provider's output pointer never enters worker work or an
/// escaping closure. Fixed 1,048-byte metadata on supported 64-bit ABIs is
/// covered by the existing 1 MiB decoder reserve; no resource limit is raised.
/// The body must not let the kernel or its pointer escape or use it concurrently.
struct CLosslessRowKernel {
    let table: UnsafePointer<SJLIACHuffman>
    let usesCodeZero: Bool

    static func withBorrowed(table: HuffmanTable, enabled: Bool, allowCodeZero: Bool = true,
                            _ body: (CLosslessRowKernel?) throws -> Void) rethrows {
        guard enabled, table.minCode.count == 17, table.maxCode.count == 17,
              table.valPtr.count == 17, table.values.count <= 256,
              table.lookaheadLength.count == 256, table.lookaheadSymbol.count == 256,
              table.valPtr.allSatisfy({ $0 >= 0 && $0 <= 256 }),
              table.lookaheadLength.allSatisfy({ $0 <= 8 }) else {
            try body(nil)
            return
        }
        // Copy the same canonical and short-prefix metadata as the C AC leaf.
        // Its scan-local preparation is avoided entirely on the scalar fallback.
        var metadata = SJLIACHuffman()
        withUnsafeMutableBytes(of: &metadata.minimum) { target in
            table.minCode.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        withUnsafeMutableBytes(of: &metadata.maximum) { target in
            table.maxCode.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        withUnsafeMutableBytes(of: &metadata.value_offsets) { target in
            for index in 0..<17 {
                target.storeBytes(of: Int64(table.valPtr[index]),
                    toByteOffset: index * MemoryLayout<Int64>.stride, as: Int64.self)
            }
        }
        withUnsafeMutableBytes(of: &metadata.values) { target in
            table.values.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        withUnsafeMutableBytes(of: &metadata.lengths) { target in
            table.lookaheadLength.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        withUnsafeMutableBytes(of: &metadata.symbols) { target in
            table.lookaheadSymbol.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        metadata.value_count = UInt32(table.values.count)
        // A table property, not an image/fixture identity: the one-bit zero
        // code carries a bounded magnitude. Its row constants need no new
        // table or allocation. Explicit opt-out retains the generic C oracle.
        let usesCodeZero = allowCodeZero && table.lookaheadLength[0] == 1
            && (1...7).contains(table.lookaheadSymbol[0])
        try withUnsafePointer(to: &metadata) { try body(.init(table: $0, usesCodeZero: usesCodeZero)) }
    }
}
