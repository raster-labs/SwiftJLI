// SPDX-License-Identifier: MIT

/// Resolves a short AC code and its magnitude in one bounded scan-local lookup.
/// Each entry stores consumed bits, coefficient advance and signed value. An
/// advance of zero denotes EOB; ZRL advances sixteen and writes an existing zero.
struct ACLookahead {
    static let bits = 13
    static let count = 1 << bits
    let entries: [UInt32]

    init?(table: HuffmanTable, blockCount: Int) {
        // Amortise construction over a substantial plane. At most three active
        // component tables occupy 96 KiB of the decoder's 1 MiB scratch reserve.
        guard blockCount >= 512 else { return nil }
        var covered = 0, hasCoveredMagnitude = false
        for prefix in 0..<256 {
            let length = Int(table.lookaheadLength[prefix])
            let category = Int(table.lookaheadSymbol[prefix] & 0x0F)
            if length > 0, length + category <= Self.bits {
                covered += 1
                hasCoveredMagnitude = hasCoveredMagnitude || category > 0
            }
        }
        // EOB/ZRL-only tables already have a cheap symbol path. Their flat
        // planes cannot amortise building a combined magnitude lookup.
        guard covered >= 128, hasCoveredMagnitude else { return nil }
        var entries = [UInt32](repeating: 0, count: Self.count)
        for prefix in 0..<Self.count {
            let shortPrefix = prefix >> (Self.bits - 8)
            let length = Int(table.lookaheadLength[shortPrefix])
            guard length > 0 else { continue }
            let symbol = table.lookaheadSymbol[shortPrefix]
            let category = Int(symbol & 0x0F), consumed = length + category
            guard consumed <= Self.bits else { continue }
            let value: Int
            if category == 0 { value = 0 }
            else {
                let magnitude = (prefix >> (Self.bits - consumed)) & ((1 << category) - 1)
                value = magnitude < (1 << (category - 1))
                    ? magnitude - ((1 << category) - 1) : magnitude
            }
            let advance = symbol == 0 ? 0 : Int(symbol >> 4) + 1
            entries[prefix] = (UInt32(consumed) << 24) | (UInt32(advance) << 16)
                | UInt32(UInt16(truncatingIfNeeded: value))
        }
        self.entries = entries
    }
}
