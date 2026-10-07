// SPDX-License-Identifier: Apache-2.0
import Foundation

/// ICC profile identifier only; never used for authentication or security.
/// Implements the MD5 compression function with explicit wrapping arithmetic.
enum ICCProfileMD5 {
    static func digest(_ input: [UInt8]) -> [UInt8] {
        var bytes = input
        let bitCount = UInt64(input.count) &* 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bitCount >> shift)) }
        var state: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476]
        let shifts = [7,12,17,22, 5,9,14,20, 4,11,16,23, 6,10,15,21]
        let constants: [UInt32] = (1...64).map { UInt32(abs(sin(Double($0))) * 4294967296) }
        for base in stride(from: 0, to: bytes.count, by: 64) {
            let words: [UInt32] = (0..<16).map { i in
                let p = base + i * 4
                return UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24
            }
            var a=state[0], b=state[1], c=state[2], d=state[3]
            for i in 0..<64 {
                let f: UInt32, g: Int
                switch i {
                case 0..<16: f=(b & c) | (~b & d); g=i
                case 16..<32: f=(d & b) | (~d & c); g=(5*i+1)%16
                case 32..<48: f=b ^ c ^ d; g=(3*i+5)%16
                default: f=c ^ (b | ~d); g=(7*i)%16
                }
                let sum = a &+ f &+ constants[i] &+ words[g]
                let shift = shifts[(i / 16) * 4 + i % 4]
                let next = b &+ ((sum << shift) | (sum >> (32-shift)))
                a=d; d=c; c=b; b=next
            }
            state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        }
        return state.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0*8)) } }
    }
}
