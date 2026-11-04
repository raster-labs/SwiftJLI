// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
struct QualifiedHuffmanDefinition {
    let bitsHex: StaticString
    let valuesHex: StaticString
    var count: Int { valuesHex.utf8CodeUnitCount / 2 }
    private func byte(_ hex: StaticString, _ index: Int) -> UInt8 {
        hex.withUTF8Buffer { bytes in
            func digit(_ c: UInt8) -> UInt8 { c <= 57 ? c - 48 : c - 87 }
            return digit(bytes[index * 2]) * 16 + digit(bytes[index * 2 + 1])
        }
    }
    func bit(_ index: Int) -> UInt8 { byte(bitsHex, index) }
    func value(_ index: Int) -> UInt8 { byte(valuesHex, index) }

}
enum QualifiedStandardHuffmanTables {
    static let dcLuminanceDefinition = QualifiedHuffmanDefinition(
        bitsHex: "00010501010101010100000000000000",
        valuesHex: "000102030405060708090a0b")
    static let dcChrominanceDefinition = QualifiedHuffmanDefinition(
        bitsHex: "00030101010101010101010000000000",
        valuesHex: "000102030405060708090a0b")
    static let acLuminanceDefinition = QualifiedHuffmanDefinition(
        bitsHex: "0002010303020403050504040000017d",
        valuesHex: "01020300041105122131410613516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9fa")
    static let acChrominanceDefinition = QualifiedHuffmanDefinition(
        bitsHex: "00020102040403040705040400010277",
        valuesHex: "000102031104052131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125f11718191a262728292a35363738393a434445464748494a535455565758595a636465666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9fa")
}
enum QualifiedHuffmanDecoder {
    static func decodeSymbolCore<Table: QualifiedHuffmanDecodeTable>(from reader: inout QualifiedBitReader, table: Table) -> QualifiedOutcome<UInt8> {
        // Fast path: resolve short (≤8-bit) codes from an 8-bit lookahead table.
        // Falls through to the bit-by-bit walk for long codes and any byte near
        // a marker / end of data, so all error and restart handling is unchanged.
        if let symbol = reader.fastDecodeSymbol(table) { return .success(symbol) }
        return decodeSymbolBitByBitCore(from: &reader, table: table)
    }
    static func decodeSymbolBitByBitCore<Table: QualifiedHuffmanDecodeTable>(
        from reader: inout QualifiedBitReader, table: Table
    ) -> QualifiedOutcome<UInt8> {
        var code: Int32 = 0

        for bitLength in 1...16 {
            let coreOutcome1 = reader.readBitCore()
            guard case .success(let bit) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
            code = (code << 1) | Int32(bit)

            if table.maxCode[bitLength] >= 0 && code <= table.maxCode[bitLength] {
                let index = table.valPtr[bitLength] + Int(code - table.minCode[bitLength])
                // A malformed DHT (e.g. a corrupted code-count byte) can yield a
                // valPtr/minCode that points past the value list; bounds-check
                // rather than trap on untrusted input.
                guard index >= 0, index < table.values.count else {
                    return .failure(QualifiedFailure(code: 130, kind: .decoding))
                }
                return .success(table.values[index])
            }
        }

        return .failure(QualifiedFailure(code: 131, kind: .decoding))
    }
    static func decodeValueCore(from reader: inout QualifiedBitReader, category cat: Int) -> QualifiedOutcome<Int32> {
        guard cat > 0 else { return .success(0) }
        guard cat <= 16 else { return .failure(QualifiedFailure(code: 132, kind: .decoding)) }

        let coreOutcome1 = reader.readBitsCore(cat)
        guard case .success(let bits) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        // If MSB is 0, the value is negative
        if bits < (1 << (cat - 1)) {
            return .success(Int32(bits) - Int32((1 << cat) - 1))
        } else {
            return .success(Int32(bits))
        }
    }
    static func decodeDCCore<Table: QualifiedHuffmanDecodeTable>(from reader: inout QualifiedBitReader, table: Table) -> QualifiedOutcome<Int32> {
        let coreOutcome1 = decodeSymbolCore(from: &reader, table: table)
        guard case .success(let coreValue1) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }
        let cat = Int(coreValue1)
        return decodeValueCore(from: &reader, category: cat)
    }
    static func decodeACCore<Table: QualifiedHuffmanDecodeTable>(from reader: inout QualifiedBitReader, table: Table,
        into out: UnsafeMutableBufferPointer<Int32>) -> QualifiedOutcome<Void> {
        precondition(out.count == 64)
        for i in 0..<64 { out[i] = 0 }

        var index = 1
        while index < 64 {
            let coreOutcome1 = decodeSymbolCore(from: &reader, table: table)
            guard case .success(let symbol) = coreOutcome1 else { return .failure(coreOutcome1.failureValue) }

            if symbol == 0x00 {
                break  // EOB — remaining coefficients are zero
            }
            if symbol == 0xF0 {
                index += 16  // ZRL — skip 16 zeros
                continue
            }

            let zeroRun = Int(symbol >> 4)
            let cat = Int(symbol & 0x0F)
            index += zeroRun
            guard index < 64 else { break }

            let coreOutcome2 = decodeValueCore(from: &reader, category: cat)
            guard case .success(let coreValue2) = coreOutcome2 else { return .failure(coreOutcome2.failureValue) }
            out[index] = coreValue2
            index += 1
        }
        return .success(())
    }
}
private func qualifiedCompileHuffman(
    bits: (Int) -> UInt8, valueCount: Int, value: (Int) -> UInt8,
    encoding: (Int, UInt16, UInt8) -> Void,
    maxCode: (Int, Int32) -> Void, minCode: (Int, Int32) -> Void,
    valPtr: (Int, Int) -> Void, lookahead: (Int, UInt8, UInt8) -> Void
) {
        // Wider than the 16-bit codes it produces so canonical-code generation
        // can't overflow on a malformed BITS array — a complete length-16 code
        // walks `code` up to 2^16, one past UInt16's range. Stored codes still
        // fit in 16 bits for any well-formed table.
        var code: UInt32 = 0
        var valueIndex = 0

        for bitLength in 1...16 {
            let count = Int(bits(bitLength - 1))
            if count > 0 {
                valPtr(bitLength, valueIndex)
                minCode(bitLength, Int32(code))
                for _ in 0..<count where valueIndex < valueCount {
                    let symbol = value(valueIndex)
                    encoding(Int(symbol), UInt16(truncatingIfNeeded: code), UInt8(bitLength))
                    // Fill every 8-bit lookahead slot whose top `bitLength` bits
                    // equal this code. A canonical code of length ≤8 is < 256,
                    // so `code << (8 - bitLength)` and its run stay in 0...255.
                    if bitLength <= 8 {
                        let shift = 8 - bitLength
                        let start = Int(code << shift)
                        for k in start..<(start + (1 << shift)) {
                            lookahead(k, UInt8(bitLength), symbol)
                        }
                    }
                    valueIndex += 1
                    code += 1
                }
                maxCode(bitLength, Int32(code - 1))
            }
            code <<= 1
        }

 }
protocol QualifiedHuffmanDecodeTable {
    associatedtype Codes: RandomAccessCollection where Codes.Index == Int, Codes.Element == Int32
    associatedtype Offsets: RandomAccessCollection where Offsets.Index == Int, Offsets.Element == Int
    associatedtype Bytes: RandomAccessCollection where Bytes.Index == Int, Bytes.Element == UInt8
    var maxCode: Codes { get }
    var minCode: Codes { get }
    var valPtr: Offsets { get }
    var values: Bytes { get }
    var lookaheadLength: Bytes { get }
    var lookaheadSymbol: Bytes { get }
}
struct QualifiedBorrowedHuffmanTable: QualifiedHuffmanDecodeTable {
    let maxCode: UnsafeMutableBufferPointer<Int32>
    let minCode: UnsafeMutableBufferPointer<Int32>
    let valPtr: UnsafeMutableBufferPointer<Int>
    let values: UnsafeMutableBufferPointer<UInt8>
    let lookaheadLength: UnsafeMutableBufferPointer<UInt8>
    let lookaheadSymbol: UnsafeMutableBufferPointer<UInt8>
    static let byteCount = 1040

    init(workspace: UnsafeMutableRawBufferPointer, valueCount: Int,
         bits: (Int) -> UInt8, value: (Int) -> UInt8) {
        precondition(workspace.count >= Self.byteCount && valueCount <= 256)
        func buffer<T>(_ type: T.Type, _ offset: Int, _ count: Int) -> UnsafeMutableBufferPointer<T> {
            UnsafeMutableRawBufferPointer(rebasing: workspace[offset..<(offset + count * MemoryLayout<T>.stride)])
                .bindMemory(to: T.self)
        }
        maxCode = buffer(Int32.self, 0, 17); minCode = buffer(Int32.self, 68, 17)
        valPtr = buffer(Int.self, 136, 17); values = buffer(UInt8.self, 272, valueCount)
        lookaheadLength = buffer(UInt8.self, 528, 256); lookaheadSymbol = buffer(UInt8.self, 784, 256)
        maxCode.initialize(repeating: -1); minCode.initialize(repeating: -1); valPtr.initialize(repeating: 0)
        lookaheadLength.initialize(repeating: 0); lookaheadSymbol.initialize(repeating: 0)
        for index in 0..<valueCount { values[index] = value(index) }
        qualifiedCompileHuffman(bits: bits, valueCount: valueCount, value: value, encoding: { _, _, _ in },
            maxCode: { maxCode[$0] = $1 }, minCode: { minCode[$0] = $1 }, valPtr: { valPtr[$0] = $1 },
            lookahead: { lookaheadLength[$0] = $1; lookaheadSymbol[$0] = $2 })
    }
}
