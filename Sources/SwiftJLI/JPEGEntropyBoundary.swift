// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Finds the next real marker without interpreting or copying entropy payload.
/// Stuffed FF00 and restart pairs remain part of the payload. Each memchr span
/// is bounded to 4096 bytes, retaining cancellation/deadline checks even when
/// the input contains no marker. The borrow ends before returning its index.
enum JPEGEntropyBoundary {
    static func find(in bytes: [UInt8], from start: Int) throws -> Int {
        try find(in: JPEGBytes(bytes), from: start)
    }

    static func find(in bytes: JPEGBytes, from start: Int) throws -> Int {
        try bytes.withUnsafeBytes { try find(in: $0, from: start) }
    }

    /// Caller retains the input owner for this synchronous scan; no pointer
    /// survives the call, including cancellation and malformed-input exits.
    static func find(in buffer: UnsafeRawBufferPointer, from start: Int) throws -> Int {
        guard start >= 0, start <= buffer.count else {
            throw CodecError(.malformedInput, "Invalid entropy scan offset.")
        }
        guard let rawBase = buffer.baseAddress else { return start }
        let base = rawBase.assumingMemoryBound(to: UInt8.self)
        let zero = SIMD16<UInt8>(repeating: 0)
        var position = start, checkEnd = start
        while position < buffer.count {
            if position >= checkEnd {
                try NativeOperation.check()
                checkEnd = position + min(4096, buffer.count - position)
            }
            while position + 33 <= checkEnd {
                let v0 = rawBase.loadUnaligned(fromByteOffset: position, as: SIMD16<UInt8>.self)
                let v1 = rawBase.loadUnaligned(fromByteOffset: position + 1, as: SIMD16<UInt8>.self)
                let w0 = rawBase.loadUnaligned(fromByteOffset: position + 16, as: SIMD16<UInt8>.self)
                let w1 = rawBase.loadUnaligned(fromByteOffset: position + 17, as: SIMD16<UInt8>.self)
                let m0 = v0.replacing(with: zero, where: v1 .== zero)
                let m1 = w0.replacing(with: zero, where: w1 .== zero)
                let combined = m0.replacing(with: m1, where: m1 .> m0)
                if combined.max() != 255 {
                    position += 32
                } else {
                    if m0.max() != 255 { position += 16 }
                    break
                }
            }
            guard let match = memchr(base + position, 255, checkEnd - position) else {
                position = checkEnd
                continue
            }
            position = base.distance(to: match.assumingMemoryBound(to: UInt8.self))
            guard position + 1 < buffer.count else { return position }
            let next = base[position + 1]
            if next == 0 || (208...215).contains(next) { position += 2 }
            else { return position }
        }
        return position
    }
}
