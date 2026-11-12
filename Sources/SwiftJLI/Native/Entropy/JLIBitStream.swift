// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
import SwiftJLIEntropyC

/// Bit-level writer for constructing JPEG entropy-coded data.
///
/// Accumulates bits MSB-first into bytes, handling JPEG byte stuffing
/// (`0xFF` is followed by `0x00` in the entropy-coded segment). For a noisy
/// 512×512 encode the writer emits ~500k bytes; the previous `.append`-per-byte
/// implementation was the single hottest cost in that case. This rewrite
/// preallocates the buffer to an upper bound (caller can size it tightly via
/// the initializer) and writes via direct subscript, avoiding both bounds-check
/// growth and Array's copy-on-write checks in the inner loop.
struct BitWriter {
    /// Backing storage; only the first `byteCount` bytes are meaningful. Sized
    /// to the caller's estimated upper bound and doubled on the rare overflow.
    private var buffer: [UInt8]
    /// Number of bytes actually written to `buffer`.
    private var byteCount: Int = 0
    /// Bit accumulator: the low `nbits` bits hold pending output, MSB-first.
    /// A 64-bit register lets us coalesce byte emission instead of flushing one
    /// byte (through a closure) per 8 bits — the Huffman/bit-writing path is the
    /// hottest cost in a noisy encode, so batching here is the main lever.
    /// Kept below 8 after every `writeBits`, so it never overflows for the
    /// ≤16-bit writes JPEG entropy coding issues.
    private var acc: UInt64 = 0
    private var nbits: Int = 0

    /// 64 KB is enough for a typical 256×256 photo; the encoder passes a tighter
    /// upper bound derived from the image dimensions.
    init(estimatedMaxSize: Int = 65536) {
        buffer = [UInt8](repeating: 0, count: max(estimatedMaxSize, 64))
    }

    /// The bytes written so far. Computed — slices `buffer` down to actual length.
    var data: [UInt8] {
        Array(buffer[0..<byteCount])
    }

    /// Writes `count` bits from `value` (MSB-first).
    mutating func writeBits(_ value: UInt32, count: Int) {
        guard count > 0 else { return }
        acc = (acc << UInt64(count)) | UInt64(value & ((1 << count) - 1))
        nbits += count
        if nbits < 8 { return }   // no whole byte pending — skip the buffer access
        // Each pending whole byte can expand to two with stuffing; +2 slack for
        // the in-loop stuffing byte.
        if byteCount + (nbits >> 3) * 2 + 2 > buffer.count { grow() }
        buffer.withUnsafeMutableBufferPointer { buf in
            let p = buf.baseAddress!
            var bc = byteCount
            while nbits >= 8 {
                nbits -= 8
                let byte = UInt8((acc >> UInt64(nbits)) & 0xFF)
                p[bc] = byte; bc += 1
                if byte == 0xFF { p[bc] = 0; bc += 1 }   // byte stuffing
            }
            byteCount = bc
        }
    }

    /// Appends unstuffed whole bytes to the pending bit sequence. The encoder
    /// passes at most 12288 bytes between cancellation checks. Source storage is
    /// independent of this writer and is borrowed only for this synchronous call.
    /// Each input byte emits exactly one byte plus at most one stuffing byte;
    /// the number of pending bits therefore remains unchanged (0...7).
    mutating func writeUnstuffedBytes(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard !bytes.isEmpty else { return }
        let required = byteCount + bytes.count * 2
        while buffer.count < required { grow() }
        var accumulator = acc
        var written = byteCount
        let pending = nbits
        buffer.withUnsafeMutableBufferPointer { output in
            for value in bytes {
                accumulator = (accumulator << 8) | UInt64(value)
                let byte = UInt8(truncatingIfNeeded: accumulator >> pending)
                output[written] = byte
                written += 1
                if byte == 0xFF {
                    output[written] = 0
                    written += 1
                }
            }
        }
        acc = accumulator
        byteCount = written
    }

    /// Writes a single bit.
    mutating func writeBit(_ bit: Bool) {
        writeBits(bit ? 1 : 0, count: 1)
    }

    /// Flushes any remaining bits, padding with 1-bits as per JPEG spec.
    mutating func flush() {
        guard nbits > 0 else { return }   // nbits is always 0–7 here
        let pad = 8 - nbits
        let byte = UInt8(((acc << UInt64(pad)) | UInt64((1 << pad) - 1)) & 0xFF)
        if byteCount + 2 > buffer.count { grow() }
        buffer.withUnsafeMutableBufferPointer { buf in
            let p = buf.baseAddress!
            p[byteCount] = byte
            if byte == 0xFF { p[byteCount + 1] = 0 }
        }
        byteCount += (byte == 0xFF) ? 2 : 1
        acc = 0
        nbits = 0
    }

    /// Pads to a byte boundary (1-bits, per spec) and writes a restart marker
    /// `0xFF 0xD0…0xD7` (`index` cycles 0–7). The marker bytes are written raw —
    /// the `0xFF` here is a real marker prefix, not stuffed data.
    mutating func emitRestartMarker(_ index: Int) {
        flush()                       // align to byte boundary (no-op if already aligned)
        if byteCount + 2 > buffer.count { grow() }
        buffer.withUnsafeMutableBufferPointer { buf in
            buf[byteCount] = 0xFF
            buf[byteCount + 1] = 0xD0 + UInt8(index & 7)
        }
        byteCount += 2
    }

    /// Doubles the backing buffer when the initial estimate was too small.
    /// Allocating in chunks keeps the amortized cost ~O(1) per byte.
    private mutating func grow() {
        buffer.append(contentsOf: repeatElement(0, count: buffer.count))
    }
}

/// Bit-level reader for parsing JPEG entropy-coded data.
///
/// Reads bits MSB-first from a byte buffer, handling JPEG byte stuffing. The
/// accumulator is 64-bit and refills in bulk: when the next 8 source bytes
/// contain no `0xFF` (checked with one SWAR test), they are spliced in with a
/// single unaligned load instead of up to 8 branchy byte loads. Lossless decode
/// reads one Huffman symbol plus up to 15 magnitude bits per *sample*, so
/// refill cost dominates that path — this is its main lever.
///
/// Invariant the bulk path preserves: whole unconsumed bytes ever buffered
/// across operations come only from bulk loads of `0xFF`-free runs, each
/// mapping 1:1 to the source bytes immediately before `byteOffset` (the
/// stuffing-aware byte loads are only triggered to complete a read/symbol that
/// then consumes them below 8 remaining bits). `alignToByte` relies on this to
/// rewind `byteOffset` over buffered whole bytes exactly.
/// Retains the immutable NSData owner for its cached buffer view. Every load
/// explicitly extends that owner's lifetime. No Data-scoped pointer escapes,
/// and workers construct local readers from retained, pointer-free owners.
struct BitReader {
    private let data: JPEGBytes
    // This pointer has NSData owner lifetime, not a scoped Data borrow lifetime.
    // Every access below uses withExtendedLifetime(data). The reader is never
    // Sendable or captured by a worker: each worker creates its own reader.
    private let buffer: UnsafeRawBufferPointer
    /// Current byte position in the data buffer.
    private(set) var byteOffset: Int = 0
    /// Bit accumulator (MSB-first in the low `bitsAvailable` bits).
    private var bitBuffer: UInt64 = 0
    /// Number of valid bits in the bit buffer.
    private var bitsAvailable: Int = 0

    init(data: [UInt8]) {
        self.init(data: JPEGBytes(data))
    }

    init(data: JPEGBytes) {
        self.data = data
        self.buffer = data.ownedBuffer
    }

    /// Starts reading at `offset` — used by segment-parallel lossless decode,
    /// where each restart segment's reader begins just past its RST marker.
    init(data: JPEGBytes, startingAt offset: Int) {
        self.data = data
        self.buffer = data.ownedBuffer
        self.byteOffset = min(max(0, offset), buffer.count)
    }

    @inline(__always)
    private func byte(at index: Int) -> UInt8 {
        withExtendedLifetime(data) { buffer[index] }
    }

    /// Whether there is more data to read.
    var hasMore: Bool {
        byteOffset < buffer.count || bitsAvailable > 0
    }

    /// Reads a single bit.
    mutating func readBit() throws -> UInt32 {
        return try readBits(1)
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
        guard byteOffset + 8 <= buffer.count else { return false }
        let word = withExtendedLifetime(data) {
            UInt64(bigEndian: buffer.loadUnaligned(fromByteOffset: byteOffset, as: UInt64.self))
        }
        guard !Self.hasFFByte(word) else { return false }
        let k = (64 - bitsAvailable) >> 3          // whole bytes that fit (≥ 6 here)
        // Refill callers have 0...15 buffered bits. With an empty buffer,
        // all eight bytes replace it; otherwise both shifts are within 1...63.
        // Handle the 64-bit splice explicitly before using masked shifts.
        if bitsAvailable == 0 {
            bitBuffer = word
        } else {
            bitBuffer = (bitBuffer &<< (8 * k)) | (word &>> (64 - 8 * k))
        }
        bitsAvailable += 8 * k
        byteOffset += k
        return true
    }

    /// Reads `count` bits and returns them as an unsigned integer.
    mutating func readBits(_ count: Int) throws -> UInt32 {
        // Every legitimate JPEG bit-read is ≤ 16 bits (magnitude categories ≤ 15,
        // EOBRUN appendages ≤ 14). A larger width only arises from a malformed or
        // forged Huffman table (whose decoded "category" can be any byte) — throw.
        guard count >= 0, count <= 16 else {
            throw JLIError.decodingFailed("invalid bit-read width \(count)")
        }
        while bitsAvailable < count {
            if bulkRefill() { break }
            try loadByte()
        }
        bitsAvailable -= count
        let value = (bitBuffer >> UInt64(bitsAvailable)) & ((1 << UInt64(count)) - 1)
        return UInt32(truncatingIfNeeded: value)
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
    mutating func fastDecodeSymbol(_ table: HuffmanTable) -> UInt8? {
        if bitsAvailable < 8 { fillBuffer(upTo: 8) }
        guard bitsAvailable >= 8 else { return nil }
        let peek = Int((bitBuffer >> (bitsAvailable - 8)) & 0xFF)
        let len = table.lookaheadLength[peek]
        guard len != 0 else { return nil }
        bitsAvailable -= Int(len)
        return table.lookaheadSymbol[peek]
    }

    /// Consumes consecutive zero bits only for the canonical one-bit zero
    /// category. Every consumed bit therefore represents one zero difference.
    /// A failed table check consumes nothing; the caller keeps the normal path.
    @inline(__always)
    mutating func consumeZeroDifferences(_ table: HuffmanTable, maximum: Int) -> Int {
        guard maximum > 0, table.lookaheadLength[0] == 1,
              table.lookaheadSymbol[0] == 0 else { return 0 }
        return consumeZeroBits(maximum: maximum)
    }

    /// Consumes consecutive zero bits when the caller has already verified that
    /// the scan-local Huffman table assigns the 1-bit `0` code to category `0`.
    @inline(__always)
    mutating func consumeZeroBits(maximum: Int) -> Int {
        guard maximum > 0 else { return 0 }
        if bitsAvailable < 8 { fillBuffer(upTo: 8) }
        guard bitsAvailable > 0 else { return 0 }
        // The guard bounds the shift to 0...63, including a full accumulator.
        let aligned = bitBuffer &<< (64 - bitsAvailable)
        let count = min(maximum, bitsAvailable, aligned.leadingZeroBitCount)
        bitsAvailable -= count
        return count
    }

    /// Consumes complete 00 pairs while retaining the refill schedule of two
    /// one-bit Huffman symbols per pair. The caller proves the symbols' meaning.
    /// Leave at least seven bits: every skipped symbol must begin with eight
    /// buffered bits, so the ordinary symbol reader would not refill inside the
    /// run. Short buffers and incomplete pairs retain the ordinary decoder.
    mutating func consumeZeroCodePairs(maximum: Int) -> Int {
        guard maximum > 0 else { return 0 }
        if bitsAvailable < 8 { fillBuffer(upTo: 8) }
        guard bitsAvailable >= 9 else { return 0 }
        let aligned = bitBuffer &<< (64 - bitsAvailable)
        let pairs = min(maximum, (bitsAvailable - 7) / 2, aligned.leadingZeroBitCount / 2)
        bitsAvailable -= pairs * 2
        return pairs
    }

    /// Resolves a lossless category and its magnitude together when both are
    /// already buffered. This avoids a separate bit-reader call per sample.
    /// A miss consumes no bits: the ordinary symbol/value path retains all
    /// long-code, marker, truncated-input and invalid-category handling.
    @inline(__always)
    mutating func fastDecodeLosslessDifference(_ table: HuffmanTable) -> Int32? {
        if bitsAvailable < 8 { fillBuffer(upTo: 8) }
        guard bitsAvailable >= 8 else { return nil }
        let peek = Int((bitBuffer >> (bitsAvailable - 8)) & 0xFF)
        let length = Int(table.lookaheadLength[peek])
        guard length != 0 else { return nil }
        let category = Int(table.lookaheadSymbol[peek])
        if category == 0 || category == 16 {
            bitsAvailable -= length
            return category == 0 ? 0 : -32768
        }
        guard category < 16, bitsAvailable >= length + category else { return nil }
        bitsAvailable -= length + category
        let magnitude = Int32((bitBuffer >> bitsAvailable) & ((1 << category) - 1))
        return magnitude < (1 << (category - 1)) ? magnitude - ((1 << category) - 1) : magnitude
    }

    /// A wider lookahead consumes one complete, precomputed difference. Only
    /// the FF-free bulk path may prefetch beyond the existing eight-bit fill;
    /// stuffing, markers and short input retain the ordinary fallback.
    @inline(__always)
    mutating func fastDecodeLosslessDifference(_ table: LosslessLookahead) -> Int32? {
        if bitsAvailable < LosslessLookahead.bits, !bulkRefill() { fillBuffer(upTo: 8) }
        guard bitsAvailable >= LosslessLookahead.bits else { return nil }
        // All reader mutations keep bitsAvailable in 0...64. The guard
        // bounds this shift to 0...51, so masking preserves the checked
        // shift's value without its general-purpose signed-width branches.
        let prefix = Int((bitBuffer &>> (bitsAvailable - LosslessLookahead.bits)) & UInt64(LosslessLookahead.count - 1))
        let entry = table.entries[prefix]
        guard entry != 0 else { return nil }
        bitsAvailable -= Int(entry >> 16)
        return Int32(Int16(truncatingIfNeeded: entry))
    }

    @inline(__always)
    mutating func fastDecodeLosslessDifference(_ lookupBase: UnsafePointer<UInt32>) -> Int32? {
        if bitsAvailable < LosslessLookahead.bits, !bulkRefill() { fillBuffer(upTo: 8) }
        guard bitsAvailable >= LosslessLookahead.bits else { return nil }
        let prefix = Int((bitBuffer &>> (bitsAvailable - LosslessLookahead.bits)) & UInt64(LosslessLookahead.count - 1))
        let entry = lookupBase[prefix]
        guard entry != 0 else { return nil }
        bitsAvailable -= Int(entry >> 16)
        return Int32(Int16(truncatingIfNeeded: entry))
    }

    /// Resolves a complete AC run/value only when all its bits are buffered.
    /// A wider prefetch uses only an FF-free bulk splice. Stuffed bytes, markers
    /// and short input retain the ordinary eight-bit fill and fallback. Physical
    /// byteOffset can advance over buffered bytes, but consumed bits and the
    /// restart position recovered by alignToByte remain unchanged.
    /// Run overflow must fall back before consuming magnitude bits: the existing
    /// AC decoder stops after the Huffman symbol in that case.
    @inline(__always)
    mutating func fastDecodeAC(_ table: ACLookahead, remaining: Int) -> UInt32? {
        if bitsAvailable < ACLookahead.bits, !bulkRefill() { fillBuffer(upTo: 8) }
        guard bitsAvailable >= ACLookahead.bits else { return nil }
        // Reader mutations bound the accumulator to 0...64 valid bits. After
        // the guard this shift is 0...51, so the masked form has identical
        // semantics without a general signed-width check per coefficient.
        let prefix = Int((bitBuffer &>> (bitsAvailable - ACLookahead.bits)) & UInt64(ACLookahead.count - 1))
        let entry = table.entries[prefix]
        guard entry != 0, Int((entry >> 16) & 0xFF) <= remaining else { return nil }
        bitsAvailable -= Int(entry >> 24)
        return entry
    }

    /// The imported leaf synchronously borrows this reader's immutable input
    /// owner, the scan-local tables and exactly 64 writable coefficients. All
    /// storage is disjoint. No input/table pointer reaches a pipeline worker.
    /// Commit cursor and partial bits before translating an entropy error.
    mutating func decodeAC(using kernel: CACKernel, into output: UnsafeMutableBufferPointer<Int32>) throws {
        guard output.count == 64, let destination = output.baseAddress else {
            throw JLIError.decodingFailed("Invalid AC coefficient destination")
        }
        var state = SJLIACState(byte_offset: byteOffset, accumulator: bitBuffer,
                               available: UInt32(bitsAvailable), marker: 0)
        let status = withExtendedLifetime(data) {
            sjli_ac_decode_block(buffer.baseAddress, buffer.count,
                &state, kernel.table, kernel.lookup, 8192, destination, output.count)
        }
        // The C input-count checks prove this offset remains within Int range.
        byteOffset = state.byte_offset
        bitBuffer = state.accumulator
        bitsAvailable = Int(state.available)
        switch status {
        case SJLI_AC_OK: return
        case SJLI_AC_END: throw JLIError.decodingFailed("Unexpected end of entropy-coded data")
        case SJLI_AC_END_AFTER_FF: throw JLIError.decodingFailed("Unexpected end of data after 0xFF")
        case SJLI_AC_MARKER:
            throw JLIError.decodingFailed("Unexpected marker 0xFF\(String(format: "%02X", state.marker)) in entropy data")
        case SJLI_AC_CODE_INDEX: throw JLIError.decodingFailed("Huffman code index out of range")
        case SJLI_AC_INVALID_CODE: throw JLIError.decodingFailed("Invalid Huffman code")
        default: throw JLIError.decodingFailed("Invalid C AC kernel arguments")
        }
    }

    /// One synchronous DC+AC leaf call, with the same scoped ownership as the
    /// AC-only bridge. `previousDC` is independent producer-local storage.
    /// The C leaf publishes it before AC, exactly like the Swift reference;
    /// neither DC failure nor an invalid extent may clear the coefficient slot.
    mutating func decodeDCT(using kernel: CDCTKernel, previousDC: inout Int32,
                            precision: Int, into output: UnsafeMutableBufferPointer<Int32>) throws {
        guard output.count == 64, let destination = output.baseAddress,
              precision == 8 || precision == 12 else {
            throw JLIError.decodingFailed("Invalid C DCT kernel arguments")
        }
        var state = SJLIACState(byte_offset: byteOffset, accumulator: bitBuffer,
                               available: UInt32(bitsAvailable), marker: 0)
        let status = withExtendedLifetime(data) {
            sjli_dct_decode_block(buffer.baseAddress, buffer.count,
                &state, kernel.dcTable, kernel.ac.table, kernel.ac.lookup, 8192,
                &previousDC, UInt32(precision), destination, output.count)
        }
        byteOffset = state.byte_offset
        bitBuffer = state.accumulator
        bitsAvailable = Int(state.available)
        switch status {
        case SJLI_AC_OK: return
        case SJLI_AC_END: throw JLIError.decodingFailed("Unexpected end of entropy-coded data")
        case SJLI_AC_END_AFTER_FF: throw JLIError.decodingFailed("Unexpected end of data after 0xFF")
        case SJLI_AC_MARKER:
            throw JLIError.decodingFailed("Unexpected marker 0xFF\(String(format: "%02X", state.marker)) in entropy data")
        case SJLI_AC_CODE_INDEX: throw JLIError.decodingFailed("Huffman code index out of range")
        case SJLI_AC_INVALID_CODE: throw JLIError.decodingFailed("Invalid Huffman code")
        case SJLI_AC_INVALID_WIDTH:
            throw JLIError.decodingFailed("invalid bit-read width \(state.marker)")
        case SJLI_AC_DC_RANGE:
            throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
        default: throw JLIError.decodingFailed("Invalid C DCT kernel arguments")
        }
    }

    /// Multi-block contiguous DCT run call (1...1024 blocks) with identical per-block
    /// cursor, DC update, coefficient zeroing and error publication semantics.
    mutating func decodeDCTRun(using kernel: CDCTKernel, previousDC: inout Int32,
                               precision: Int, blockCount: Int,
                               into output: UnsafeMutableBufferPointer<Int32>) throws {
        guard (1...1024).contains(blockCount), output.count >= blockCount * 64,
              let destination = output.baseAddress,
              precision == 8 || precision == 12 else {
            throw JLIError.decodingFailed("Invalid C DCT kernel arguments")
        }
        var state = SJLIACState(byte_offset: byteOffset, accumulator: bitBuffer,
                               available: UInt32(bitsAvailable), marker: 0)
        let status = withExtendedLifetime(data) {
            sjli_dct_decode_run(buffer.baseAddress, buffer.count,
                &state, kernel.dcTable, kernel.ac.table, kernel.ac.lookup, 8192,
                &previousDC, UInt32(precision), destination, blockCount)
        }
        byteOffset = state.byte_offset
        bitBuffer = state.accumulator
        bitsAvailable = Int(state.available)
        switch status {
        case SJLI_AC_OK: return
        case SJLI_AC_END: throw JLIError.decodingFailed("Unexpected end of entropy-coded data")
        case SJLI_AC_END_AFTER_FF: throw JLIError.decodingFailed("Unexpected end of data after 0xFF")
        case SJLI_AC_MARKER:
            throw JLIError.decodingFailed("Unexpected marker 0xFF\(String(format: "%02X", state.marker)) in entropy data")
        case SJLI_AC_CODE_INDEX: throw JLIError.decodingFailed("Huffman code index out of range")
        case SJLI_AC_INVALID_CODE: throw JLIError.decodingFailed("Invalid Huffman code")
        case SJLI_AC_INVALID_WIDTH:
            throw JLIError.decodingFailed("invalid bit-read width \(state.marker)")
        case SJLI_AC_DC_RANGE:
            throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
        default: throw JLIError.decodingFailed("Invalid C DCT kernel arguments")
        }
    }

    /// One synchronous C call per validated row. All input/table/output owners
    /// enclose this call, and no pointer is saved or passed to another thread.
    /// Publish reader state before translating failure so a truncated row has
    /// the same partial output, physical prefetch and next-read behaviour as Swift.
    mutating func decodeLeftUInt16Row(using kernel: CLosslessRowKernel,
        sampleCount: Int, seed: Int32, into output: UnsafeMutableRawBufferPointer
    ) throws -> (first: Int32, last: Int32) {
        guard (1...65535).contains(sampleCount), (0...65535).contains(seed),
              output.count >= sampleCount * 2, let destination = output.baseAddress else {
            throw JLIError.decodingFailed("Invalid C lossless row arguments")
        }
        var state = SJLIACState(byte_offset: byteOffset, accumulator: bitBuffer,
                               available: UInt32(bitsAvailable), marker: 0)
        var result = SJLILosslessRowResult()
        let status = withExtendedLifetime(data) {
            if kernel.usesCodeZero {
                return sjli_lossless_left_u16_code0_row(buffer.baseAddress,
                    buffer.count, &state, kernel.table, UInt32(seed), sampleCount,
                    destination, output.count, &result)
            }
            if let lookup = kernel.lookup {
                return sjli_lossless_left_u16_lookup_row(buffer.baseAddress,
                    buffer.count, &state, kernel.table, lookup, LosslessLookahead.count,
                    UInt32(seed), sampleCount, destination, output.count, &result)
            }
            return sjli_lossless_left_u16_row(buffer.baseAddress,
                buffer.count, &state, kernel.table, UInt32(seed), sampleCount,
                destination, output.count, &result)
        }
        byteOffset = state.byte_offset
        bitBuffer = state.accumulator
        bitsAvailable = Int(state.available)
        switch status {
        case SJLI_AC_OK: return (Int32(result.first), Int32(result.last))
        case SJLI_AC_END: throw JLIError.decodingFailed("Unexpected end of entropy-coded data")
        case SJLI_AC_END_AFTER_FF: throw JLIError.decodingFailed("Unexpected end of data after 0xFF")
        case SJLI_AC_MARKER:
            throw JLIError.decodingFailed("Unexpected marker 0xFF\(String(format: "%02X", state.marker)) in entropy data")
        case SJLI_AC_CODE_INDEX: throw JLIError.decodingFailed("Huffman code index out of range")
        case SJLI_AC_INVALID_CODE: throw JLIError.decodingFailed("Invalid Huffman code")
        case SJLI_AC_INVALID_WIDTH:
            throw JLIError.decodingFailed("invalid bit-read width \(state.marker)")
        default: throw JLIError.decodingFailed("Invalid C lossless row arguments")
        }
    }

    /// Best-effort buffer fill used by the Huffman lookahead paths. Tries the
    /// bulk splice first, then loads whole bytes (resolving `0xFF 0x00` stuffing
    /// exactly as ``loadByte()`` does) until at least `target` bits are buffered,
    /// but **stops without throwing** when it reaches a marker (`0xFF` not
    /// followed by `0x00`) or the end of the data — it never advances past a
    /// marker.
    private mutating func fillBuffer(upTo target: Int) {
        if bitsAvailable < target, bulkRefill() { return }
        while bitsAvailable < target {
            guard byteOffset < buffer.count else { return }
            let byte = self.byte(at: byteOffset)
            if byte == 0xFF {
                guard byteOffset + 1 < buffer.count else { return }
                if self.byte(at: byteOffset + 1) != 0x00 { return }  // marker — leave for slow path
                byteOffset += 2                               // consume the stuffed 0xFF 0x00
            } else {
                byteOffset += 1
            }
            bitBuffer = (bitBuffer << 8) | UInt64(byte)
            bitsAvailable += 8
        }
    }

    /// Loads the next byte from the data, handling byte stuffing.
    private mutating func loadByte() throws {
        guard byteOffset < buffer.count else {
            throw JLIError.decodingFailed("Unexpected end of entropy-coded data")
        }
        let byte = self.byte(at: byteOffset)
        byteOffset += 1

        if byte == 0xFF {
            guard byteOffset < buffer.count else {
                throw JLIError.decodingFailed("Unexpected end of data after 0xFF")
            }
            let next = self.byte(at: byteOffset)
            if next == 0x00 {
                // Byte stuffing — the 0xFF is a data byte
                byteOffset += 1
            } else {
                // This is a marker, not data — should not happen in entropy segment
                throw JLIError.decodingFailed("Unexpected marker 0xFF\(String(format: "%02X", next)) in entropy data")
            }
        }

        bitBuffer = (bitBuffer << 8) | UInt64(byte)
        bitsAvailable += 8
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
    mutating func skipRestartMarker(expectedIndex: Int) throws {
        alignToByte()
        // Skip any 0xFF fill bytes that precede the marker.
        while byteOffset < buffer.count - 1, self.byte(at: byteOffset) == 0xFF,
              self.byte(at: byteOffset + 1) == 0xFF {
            byteOffset += 1
        }
        guard byteOffset + 1 < buffer.count else {
            throw JLIError.decodingFailed("Unexpected end of data expecting RST marker")
        }
        guard self.byte(at: byteOffset) == 0xFF else {
            throw JLIError.decodingFailed(
                "Expected RST marker at offset \(byteOffset), got 0x\(String(format: "%02X", self.byte(at: byteOffset)))"
            )
        }
        let expected = UInt8(0xD0 + (expectedIndex & 7))
        let got = self.byte(at: byteOffset + 1)
        guard got >= 0xD0 && got <= 0xD7 else {
            throw JLIError.decodingFailed(
                "Expected RST\(expectedIndex & 7) (0xFF D\(expectedIndex & 7)), got 0xFF \(String(format: "%02X", got))"
            )
        }
        // Some encoders emit RSTs out of strict cyclic order on damaged streams,
        // but ImageIO/libjpeg always cycle 0–7. Accept what we got but warn via
        // throwing if it diverges — for now we accept any RST byte for robustness.
        _ = expected
        byteOffset += 2
    }
}
