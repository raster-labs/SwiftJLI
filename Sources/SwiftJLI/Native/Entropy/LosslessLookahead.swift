// SPDX-License-Identifier: Apache-2.0

/// One bounded scan-local table resolves a short Huffman code and its signed
/// difference together. Zero entries use the ordinary checked decoder.
struct LosslessLookahead {
    static let bits = 13
    static let count = 1 << bits
    let entries: [UInt32]

    init?(table: HuffmanTable, sampleCount: Int) {
        // Amortise the 8192-entry construction over at least twice that many
        // samples. No table/cache survives the synchronous scan operation.
        guard sampleCount >= Self.count * 2, table.values.count >= 3 else { return nil }
        var covered = 0, valid = 0, categories: UInt32 = 0
        table.lookaheadLength.withUnsafeBufferPointer { lenBuf in
            table.lookaheadSymbol.withUnsafeBufferPointer { symBuf in
                guard let lenBase = lenBuf.baseAddress, let symBase = symBuf.baseAddress else { return }
                for prefix in 0..<256 {
                    let length = Int(lenBase[prefix])
                    guard length > 0 else { continue }
                    valid += 1
                    let category = Int(symBase[prefix])
                    let magnitudeBits = category == 16 ? 0 : category
                    if category <= 16, length + magnitudeBits <= Self.bits {
                        covered += 1
                        categories |= 1 << category
                    }
                }
            }
        }
        // Long-magnitude tables (typically noisy images) should not pay an
        // extra failed lookup for every sample. Canonical prefix coverage is
        // only a dispatch heuristic; every uncovered value keeps its fallback.
        // A nearly constant category already has a cheap, predictable fused
        // path; table dispatch is reserved for heterogeneous short values.
        guard valid > 0, covered * 2 >= valid, categories.nonzeroBitCount >= 3 else { return nil }
        self.entries = Array<UInt32>(unsafeUninitializedCapacity: Self.count) { buffer, initializedCount in
            guard let base = buffer.baseAddress else {
                initializedCount = 0
                return
            }
            table.lookaheadLength.withUnsafeBufferPointer { lenBuf in
                table.lookaheadSymbol.withUnsafeBufferPointer { symBuf in
                    guard let lenBase = lenBuf.baseAddress, let symBase = symBuf.baseAddress else {
                        base.initialize(repeating: 0, count: Self.count)
                        return
                    }
                    for shortPrefix in 0..<256 {
                        let blockBase = base + (shortPrefix << 5)
                        let length = Int(lenBase[shortPrefix])
                        guard length > 0 else {
                            blockBase.initialize(repeating: 0, count: 32)
                            continue
                        }
                        let category = Int(symBase[shortPrefix])
                        let magnitudeBits = category == 16 ? 0 : category
                        let consumed = length + magnitudeBits
                        guard category <= 16, consumed <= Self.bits else {
                            blockBase.initialize(repeating: 0, count: 32)
                            continue
                        }
                        let header = UInt32(consumed) << 16
                        if category == 0 {
                            blockBase.initialize(repeating: header, count: 32)
                        } else if category == 16 {
                            blockBase.initialize(repeating: header | 0x8000, count: 32)
                        } else if consumed <= 8 {
                            let magnitude = (shortPrefix >> (8 - consumed)) & ((1 << category) - 1)
                            let difference = Int32(magnitude < (1 << (category - 1))
                                ? magnitude - ((1 << category) - 1) : magnitude)
                            let entry = header | UInt32(UInt16(truncatingIfNeeded: difference))
                            blockBase.initialize(repeating: entry, count: 32)
                        } else {
                            let shift = Self.bits - consumed
                            let mask = (1 << category) - 1
                            let threshold = 1 << (category - 1)
                            let prefixBase = shortPrefix << 5
                            for low in 0..<32 {
                                let prefix = prefixBase | low
                                let magnitude = (prefix >> shift) & mask
                                let difference = Int32(magnitude < threshold ? magnitude - mask : magnitude)
                                blockBase[low] = header | UInt32(UInt16(truncatingIfNeeded: difference))
                            }
                        }
                    }
                }
            }
            initializedCount = Self.count
        }
    }
}

