// SPDX-License-Identifier: Apache-2.0

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
        guard blockCount >= 512,
              table.lookaheadLength.count == 256,
              table.lookaheadSymbol.count == 256 else { return nil }
        let built: [UInt32]? = table.lookaheadLength.withUnsafeBufferPointer { lengths in
            table.lookaheadSymbol.withUnsafeBufferPointer { symbols in
                let lenBase = lengths.baseAddress!
                let symBase = symbols.baseAddress!
                var covered = 0, hasCoveredMagnitude = false
                for prefix in 0..<256 {
                    let length = Int(lenBase[prefix])
                    let category = Int(symBase[prefix] & 0x0F)
                    if length > 0, length + category <= Self.bits {
                        covered += 1
                        hasCoveredMagnitude = hasCoveredMagnitude || category > 0
                    }
                }
                // EOB/ZRL-only tables already have a cheap symbol path. Their flat
                // planes cannot amortise building a combined magnitude lookup.
                guard covered >= 128, hasCoveredMagnitude else { return nil }
                return [UInt32](unsafeUninitializedCapacity: Self.count) { buffer, initializedCount in
                    let dst = buffer.baseAddress!
                    for shortPrefix in 0..<256 {
                        let baseIndex = shortPrefix << 5
                        let length = Int(lenBase[shortPrefix])
                        guard length > 0 else {
                            (dst + baseIndex).initialize(repeating: 0, count: 32)
                            continue
                        }
                        let symbol = symBase[shortPrefix]
                        let category = Int(symbol & 0x0F), consumed = length + category
                        guard consumed <= Self.bits else {
                            (dst + baseIndex).initialize(repeating: 0, count: 32)
                            continue
                        }
                        let advance = symbol == 0 ? 0 : Int(symbol >> 4) + 1
                        let header = (UInt32(consumed) << 24) | (UInt32(advance) << 16)
                        if category == 0 {
                            (dst + baseIndex).initialize(repeating: header, count: 32)
                        } else if consumed <= 8 {
                            let mask = (1 << category) - 1
                            let half = 1 << (category - 1)
                            let magnitude = (shortPrefix >> (8 - consumed)) & mask
                            let value = magnitude < half ? magnitude - mask : magnitude
                            let entry = header | UInt32(UInt16(truncatingIfNeeded: value))
                            (dst + baseIndex).initialize(repeating: entry, count: 32)
                        } else {
                            let shift = Self.bits - consumed
                            let mask = (1 << category) - 1
                            let half = 1 << (category - 1)
                            for suffix in 0..<32 {
                                let prefix = baseIndex | suffix
                                let magnitude = (prefix >> shift) & mask
                                let value = magnitude < half ? magnitude - mask : magnitude
                                dst[prefix] = header | UInt32(UInt16(truncatingIfNeeded: value))
                            }
                        }
                    }
                    initializedCount = Self.count
                }
            }
        }
        guard let entries = built else { return nil }
        self.entries = entries
    }
}
