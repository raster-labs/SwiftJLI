// SPDX-License-Identifier: MIT

/// One bounded scan-local table resolves a short Huffman code and its signed
/// difference together. Zero entries use the ordinary checked decoder.
struct LosslessLookahead {
    static let bits = 13
    static let count = 1 << bits
    let entries: [UInt32]

    init?(table: HuffmanTable, sampleCount: Int) {
        // Amortise the 8192-entry construction over at least twice that many
        // samples. No table/cache survives the synchronous scan operation.
        guard sampleCount >= Self.count * 2 else { return nil }
        var covered = 0, valid = 0, categories: UInt32 = 0
        for prefix in 0..<256 {
            let length = Int(table.lookaheadLength[prefix])
            guard length > 0 else { continue }
            valid += 1
            let category = Int(table.lookaheadSymbol[prefix])
            let magnitudeBits = category == 16 ? 0 : category
            if category <= 16, length + magnitudeBits <= Self.bits {
                covered += 1
                categories |= 1 << category
            }
        }
        // Long-magnitude tables (typically noisy images) should not pay an
        // extra failed lookup for every sample. Canonical prefix coverage is
        // only a dispatch heuristic; every uncovered value keeps its fallback.
        // A nearly constant category already has a cheap, predictable fused
        // path; table dispatch is reserved for heterogeneous short values.
        guard valid > 0, covered * 2 >= valid, categories.nonzeroBitCount >= 3 else { return nil }
        var entries = [UInt32](repeating: 0, count: Self.count)
        for prefix in 0..<Self.count {
            let shortPrefix = prefix >> (Self.bits - 8)
            let length = Int(table.lookaheadLength[shortPrefix])
            guard length > 0 else { continue }
            let category = Int(table.lookaheadSymbol[shortPrefix])
            let magnitudeBits = category == 16 ? 0 : category
            let consumed = length + magnitudeBits
            guard category <= 16, consumed <= Self.bits else { continue }
            let difference: Int32
            if category == 0 { difference = 0 }
            else if category == 16 { difference = -32768 }
            else {
                let magnitude = (prefix >> (Self.bits - consumed)) & ((1 << category) - 1)
                difference = Int32(magnitude < (1 << (category - 1))
                    ? magnitude - ((1 << category) - 1) : magnitude)
            }
            entries[prefix] = (UInt32(consumed) << 16) | UInt32(UInt16(truncatingIfNeeded: difference))
        }
        self.entries = entries
    }
}

