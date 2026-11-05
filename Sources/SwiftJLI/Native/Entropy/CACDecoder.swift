// SPDX-License-Identifier: Apache-2.0
import SwiftJLIEntropyC

/// A non-Sendable, synchronous scan-local borrow. Only the entropy producer
/// receives it; reconstruction workers receive coefficients, never these
/// pointers. The metadata and existing 32 KiB lookup owners enclose the entire
/// producer loop. No per-block table conversion, allocation or copy occurs.
struct CACKernel {
    let table: UnsafePointer<SJLIACHuffman>
    let lookup: UnsafePointer<UInt32>

    static func metadata(for table: HuffmanTable) -> SJLIACHuffman? {
        guard table.minCode.count == 17, table.maxCode.count == 17,
              table.valPtr.count == 17, table.values.count <= 256,
              table.lookaheadLength.count == 256, table.lookaheadSymbol.count == 256,
              table.valPtr.allSatisfy({ $0 >= 0 && $0 <= 256 }),
              table.lookaheadLength.allSatisfy({ $0 <= 8 }) else {
            return nil
        }
        // Fixed stack metadata is bounded by 1,048 bytes on the supported
        // 64-bit ABIs, covered by the existing 1 MiB decoder scratch reserve.
        // Each tuple borrow covers only its own imported C array member.
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
        return metadata
    }

    static func withBorrowed(table: HuffmanTable, lookup: ACLookahead?, enabled: Bool,
                             _ body: (CACKernel?) throws -> Void) rethrows {
        guard enabled, let lookup, lookup.entries.count == 8192,
              var metadata = metadata(for: table) else {
            try body(nil)
            return
        }
        try withUnsafePointer(to: &metadata) { tablePointer in
            try lookup.entries.withUnsafeBufferPointer { entries in
                // The exact positive count guard proves a non-nil base.
                guard let base = entries.baseAddress else { try body(nil); return }
                try body(.init(table: tablePointer, lookup: base))
            }
        }
    }
}

/// Both fixed Huffman wire values are built once per scan. Their borrows and
/// the existing combined AC lookup enclose only the synchronous producer;
/// neither metadata pointer is Sendable or passed to reconstruction workers.
struct CDCTKernel {
    let dcTable: UnsafePointer<SJLIACHuffman>
    let ac: CACKernel

    static func withBorrowed(dcTable: HuffmanTable, acTable: HuffmanTable,
                             lookup: ACLookahead?, enabled: Bool,
                             _ body: (CDCTKernel?) throws -> Void) rethrows {
        guard enabled, let lookup, lookup.entries.count == 8192,
              var dcMetadata = CACKernel.metadata(for: dcTable) else {
            try body(nil)
            return
        }
        try CACKernel.withBorrowed(table: acTable, lookup: lookup, enabled: enabled) { ac in
            guard let ac else { try body(nil); return }
            try withUnsafePointer(to: &dcMetadata) { dc in
                try body(.init(dcTable: dc, ac: ac))
            }
        }
    }
}
