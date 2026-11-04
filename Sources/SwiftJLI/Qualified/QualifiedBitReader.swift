// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
struct QualifiedBitReader {
    private let data: QualifiedByteView
    /// Current byte position in the data buffer.
    private(set) var byteOffset: Int = 0
    /// Bit accumulator (MSB-first in the low `bitsAvailable` bits).
    private var bitBuffer: UInt64 = 0
    /// Number of valid bits in the bit buffer.
    private var bitsAvailable: Int = 0



    /// Starts reading at `offset` — used by segment-parallel lossless decode,
    /// where each restart segment's reader begins just past its RST marker.


    init(borrowing data: UnsafeRawBufferPointer) { self.data = QualifiedByteView(borrowing: data) }


    /// Whether there is more data to read.
    var hasMore: Bool {
        byteOffset < data.count || bitsAvailable > 0
    }

    /// Reads a single bit.
    mutating func readBitCore() -> QualifiedOutcome<UInt32> {
        return readBitsCore(1)
    }

    /// True when any byte of `x` equals `0xFF` (SWAR zero-byte test on `~x`).
    @inline(__always)
    private static func hasFFByte(_ x: UInt64) -> Bool {
        let y = ~x
        return ((y &- 0x0101_0101_0101_0101) & ~y & 0x8080_8080_8080_8080) != 0
    }

    /// Bulk-splices up to 8 source bytes into the accumulator with one load when
    /// the next 8 bytes are plain data (no `0xFF` anywhere — conservatively
    /// covering stuffing *and* markers, so the byte-wise path keeps sole
    /// ownership of both). Returns `false` when the bulk path doesn't apply.
    @inline(__always)
    private mutating func bulkRefill() -> Bool {
        guard byteOffset + 8 <= data.count else { return false }
        let word = data.withUnsafeBytes { buf in
            UInt64(bigEndian: (buf.baseAddress! + byteOffset)
                .loadUnaligned(as: UInt64.self))
        }
        guard !Self.hasFFByte(word) else { return false }
        let k = (64 - bitsAvailable) >> 3          // whole bytes that fit (≥ 6 here)
        bitBuffer = (bitBuffer << (8 * k)) | (word >> (64 - 8 * k))
        bitsAvailable += 8 * k
        byteOffset += k
        return true
    }

    /// Reads `count` bits and returns them as an unsigned integer.
    mutating func readBitsCore(_ count: Int) -> QualifiedOutcome<UInt32> {
        // Every legitimate JPEG bit-read is ≤ 16 bits (magnitude categories ≤ 15,
        // EOBRUN appendages ≤ 14). A larger width only arises from a malformed or
        // forged Huffman table (whose decoded "category" can be any byte) — throw.
        guard count >= 0, count <= 16 else {
            return .failure(QualifiedFailure(code: 123, kind: .decoding, detail0: Int(count)))
        }
        while bitsAvailable < count {
            if bulkRefill() { break }
            if case .failure(let failure) = loadByte() { return .failure(failure) }
        }
        bitsAvailable -= count
        let value = (bitBuffer >> UInt64(bitsAvailable)) & ((1 << UInt64(count)) - 1)
        return .success(UInt32(truncatingIfNeeded: value))
    }

    /// Table-driven fast path for short (≤8-bit) Huffman codes.
    ///
    /// Best-effort fills the buffer to 8 bits (without throwing), peeks the top
    /// byte, and — if it resolves to a complete ≤8-bit code in `table` — consumes
    /// exactly that code's bits and returns its symbol. Returns `nil` (consuming
    /// nothing) when the code is longer than 8 bits or when 8 bits can't be
    /// safely buffered (a marker or end-of-data is within reach). In every
    /// `nil` case the caller falls back to the throwing bit-by-bit reader, which
    /// is the sole owner of long-code, marker, EOF, and malformed-table handling.
    /// Because the lookahead table is derived from the same canonical codes and
    /// the prefix-free property holds, a non-`nil` result is bit-for-bit what the
    /// bit-by-bit walk would have produced.
    mutating func fastDecodeSymbol<Table: QualifiedHuffmanDecodeTable>(_ table: Table) -> UInt8? {
        if bitsAvailable < 8 { fillBuffer(upTo: 8) }
        guard bitsAvailable >= 8 else { return nil }
        let peek = Int((bitBuffer >> (bitsAvailable - 8)) & 0xFF)
        let len = table.lookaheadLength[peek]
        guard len != 0 else { return nil }
        bitsAvailable -= Int(len)
        return table.lookaheadSymbol[peek]
    }

    /// Best-effort buffer fill used only by ``fastDecodeSymbol(_:)``. Tries the
    /// bulk splice first, then loads whole bytes (resolving `0xFF 0x00` stuffing
    /// exactly as ``loadByte()`` does) until at least `target` bits are buffered,
    /// but **stops without throwing** when it reaches a marker (`0xFF` not
    /// followed by `0x00`) or the end of the data — it never advances past a
    /// marker.
    private mutating func fillBuffer(upTo target: Int) {
        if bitsAvailable < target, bulkRefill() { return }
        while bitsAvailable < target {
            guard byteOffset < data.count else { return }
            let byte = data[byteOffset]
            if byte == 0xFF {
                guard byteOffset + 1 < data.count else { return }
                if data[byteOffset + 1] != 0x00 { return }  // marker — leave for slow path
                byteOffset += 2                               // consume the stuffed 0xFF 0x00
            } else {
                byteOffset += 1
            }
            bitBuffer = (bitBuffer << 8) | UInt64(byte)
            bitsAvailable += 8
        }
    }

    /// Loads the next byte from the data, handling byte stuffing.
    private mutating func loadByte() -> QualifiedOutcome<Void> {
        guard byteOffset < data.count else {
            return .failure(QualifiedFailure(code: 124, kind: .decoding))
        }
        let byte = data[byteOffset]
        byteOffset += 1

        if byte == 0xFF {
            guard byteOffset < data.count else {
                return .failure(QualifiedFailure(code: 125, kind: .decoding))
            }
            let next = data[byteOffset]
            if next == 0x00 {
                // Byte stuffing — the 0xFF is a data byte
                byteOffset += 1
            } else {
                // This is a marker, not data — should not happen in entropy segment
                return .failure(QualifiedFailure(code: 126, kind: .decoding, detail0: Int(next)))
            }
        }

        bitBuffer = (bitBuffer << 8) | UInt64(byte)
        bitsAvailable += 8
        return .success(())
    }

    /// Aligns the reader to the next byte boundary by discarding the partial
    /// byte's remaining bits. Whole unconsumed buffered bytes (which exist only
    /// via the bulk path's 1:1, `0xFF`-free loads — see the type doc) are
    /// returned to the source by rewinding `byteOffset`, so marker scanning
    /// resumes at the true byte position.
    mutating func alignToByte() {
        byteOffset -= bitsAvailable >> 3
        bitsAvailable = 0
        bitBuffer = 0
    }

    /// Consumes a restart marker (`FF D<expectedIndex>`) at the current byte position.
    ///
    /// Called by the decoder after every `restartInterval` MCUs when the JPEG carries
    /// DRI + RST markers. Discards any partial bits first (restart markers always sit
    /// on byte boundaries), then advances past the two-byte marker. The marker index
    /// cycles 0–7 (`RST0`–`RST7`), so the caller passes `mcuCount / restartInterval & 7`.
    ///
    /// JPEG allows fill bytes (`0xFF 0xFF…`) before any marker; we tolerate them here.
    mutating func skipRestartMarkerCore(expectedIndex: Int) -> QualifiedOutcome<Void> {
        alignToByte()
        // Skip any 0xFF fill bytes that precede the marker.
        while byteOffset < data.count - 1, data[byteOffset] == 0xFF,
              data[byteOffset + 1] == 0xFF {
            byteOffset += 1
        }
        guard byteOffset + 1 < data.count else {
            return .failure(QualifiedFailure(code: 127, kind: .decoding))
        }
        guard data[byteOffset] == 0xFF else {
            return .failure(QualifiedFailure(code: 128, kind: .decoding, detail0: Int(byteOffset), detail1: Int(data[byteOffset])))
        }
        let expected = UInt8(0xD0 + (expectedIndex & 7))
        let got = data[byteOffset + 1]
        guard got >= 0xD0 && got <= 0xD7 else {
            return .failure(QualifiedFailure(code: 129, kind: .decoding, detail0: Int(expectedIndex & 7), detail1: Int(expectedIndex & 7), detail2: Int(got)))
        }
        // Some encoders emit RSTs out of strict cyclic order on damaged streams,
        // but ImageIO/libjpeg always cycle 0–7. Accept what we got but warn via
        // throwing if it diverges — for now we accept any RST byte for robustness.
        _ = expected
        byteOffset += 2
        return .success(())
    }
}
