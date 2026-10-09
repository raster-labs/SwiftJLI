// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Finds the next real marker without interpreting or copying entropy payload.
/// Stuffed FF00 and restart pairs remain part of the payload. Each memchr span
/// is bounded to 4096 bytes, retaining cancellation/deadline checks even when
/// the input contains no marker. The borrow ends before returning its index.
enum JPEGEntropyBoundary {
    static func find(in bytes: [UInt8], from start: Int) throws -> Int {
        guard start >= 0, start <= bytes.count else {
            throw CodecError(.malformedInput, "Invalid entropy scan offset.")
        }
        return try bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return start }
            var position = start, checkEnd = start
            while position < buffer.count {
                if position >= checkEnd {
                    try NativeOperation.check()
                    checkEnd = position + min(4096, buffer.count - position)
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
}
