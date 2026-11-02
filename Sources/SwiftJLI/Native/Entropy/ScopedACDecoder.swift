// SPDX-License-Identifier: Apache-2.0

extension HuffmanDecoder {
    /// Decodes a block directly into its scoped coefficient-plane borrow.
    /// The caller retains that plane until this synchronous call finishes.
    /// All 64 slots are cleared, including on a later entropy failure, exactly
    /// as in the retained array implementation used by the reference path.
    static func decodeAC(
        from reader: inout BitReader, table: HuffmanTable,
        into output: UnsafeMutableBufferPointer<Int32>
    ) throws {
        guard output.count == 64, let coefficients = output.baseAddress else {
            throw JLIError.decodingFailed("Invalid AC coefficient destination")
        }
        coefficients.update(repeating: 0, count: 64)
        var index = 1
        while index < 64 {
            let symbol = try decodeSymbol(from: &reader, table: table)
            if symbol == 0x00 { break }
            if symbol == 0xF0 {
                index += 16
                continue
            }
            index += Int(symbol >> 4)
            guard index < 64 else { break }
            coefficients[index] = try decodeValue(from: &reader, category: Int(symbol & 0x0F))
            index += 1
        }
    }

    /// The lookup is chosen once per block, outside the coefficient loop.
    /// Uncovered codes and boundary cases retain the ordinary decoder below.
    static func decodeAC(
        from reader: inout BitReader, table: HuffmanTable, lookup: ACLookahead,
        into output: UnsafeMutableBufferPointer<Int32>
    ) throws {
        guard output.count == 64, let coefficients = output.baseAddress else {
            throw JLIError.decodingFailed("Invalid AC coefficient destination")
        }
        coefficients.update(repeating: 0, count: 64)
        var index = 1
        while index < 64 {
            if let entry = reader.fastDecodeAC(lookup, remaining: 64 - index) {
                let advance = Int((entry >> 16) & 0xFF)
                if advance == 0 { break }
                index += advance
                coefficients[index - 1] = Int32(Int16(truncatingIfNeeded: entry))
                continue
            }
            let symbol = try decodeSymbol(from: &reader, table: table)
            if symbol == 0x00 { break }
            if symbol == 0xF0 {
                index += 16
                continue
            }
            index += Int(symbol >> 4)
            guard index < 64 else { break }
            coefficients[index] = try decodeValue(from: &reader, category: Int(symbol & 0x0F))
            index += 1
        }
    }
}
