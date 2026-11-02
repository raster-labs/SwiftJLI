import Foundation

@inline(never)
func scalar(_ source: UnsafeRawBufferPointer, _ destination: UnsafeMutableRawBufferPointer,
            sourceOffset: Int, destinationOffset: Int, count: Int) {
    for offset in stride(from: 0, to: count, by: 2) {
        destination[destinationOffset + offset] = source[sourceOffset + offset + 1]
        destination[destinationOffset + offset + 1] = source[sourceOffset + offset]
    }
}

@inline(never)
func words(_ source: UnsafeRawBufferPointer, _ destination: UnsafeMutableRawBufferPointer,
           sourceOffset: Int, destinationOffset: Int, count: Int) {
    let wordBytes = count - count % MemoryLayout<UInt64>.size
    for offset in stride(from: 0, to: wordBytes, by: MemoryLayout<UInt64>.size) {
        let word = source.loadUnaligned(fromByteOffset: sourceOffset + offset, as: UInt64.self)
        let swapped = ((word & 0x00FF00FF00FF00FF) << 8) | ((word >> 8) & 0x00FF00FF00FF00FF)
        destination.storeBytes(of: swapped, toByteOffset: destinationOffset + offset, as: UInt64.self)
    }
    for offset in stride(from: wordBytes, to: count, by: 2) {
        destination[destinationOffset + offset] = source[sourceOffset + offset + 1]
        destination[destinationOffset + offset + 1] = source[sourceOffset + offset]
    }
}

var source = Data(count: 2048 * 2048 * 2 + 16)
source.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
    for index in 0..<raw.count { raw[index] = UInt8(truncatingIfNeeded: index &* 73 &+ index / 127) }
}
// Verify every tail and unaligned source/destination start with guard bytes.
var verificationCases = 0
for size in stride(from: 0, through: 512, by: 2) {
    for sourceOffset in 0..<8 {
        for destinationOffset in 0..<8 {
            var expected = Data(repeating: 0xA5, count: 528)
            var actual = expected
            source.withUnsafeBytes { raw in
                expected.withUnsafeMutableBytes { scalar(raw, $0, sourceOffset: sourceOffset, destinationOffset: destinationOffset, count: size) }
                actual.withUnsafeMutableBytes { words(raw, $0, sourceOffset: sourceOffset, destinationOffset: destinationOffset, count: size) }
            }
            precondition(actual == expected)
            verificationCases += 1
        }
    }
}
print("verified \(verificationCases) exact conversion/alignment/tail cases")
if CommandLine.arguments.contains("--verify-only") { exit(0) }
var scratch = Data(count: 64 * 1024)
var scalarMS = [Double]()
var wordsMS = [Double]()
for trial in 0..<25 {
    for useWords in (trial % 2 == 0 ? [false, true] : [true, false]) {
        let start = ContinuousClock.now
        source.withUnsafeBytes { raw in
            scratch.withUnsafeMutableBytes { destination in
                for firstRow in stride(from: 0, to: 2048, by: 16) {
                    for row in 0..<16 {
                        if useWords {
                            words(raw, destination, sourceOffset: (firstRow + row) * 4096, destinationOffset: row * 4096, count: 4096)
                        } else {
                            scalar(raw, destination, sourceOffset: (firstRow + row) * 4096, destinationOffset: row * 4096, count: 4096)
                        }
                    }
                }
            }
        }
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        if trial >= 5 {
            if useWords { wordsMS.append(milliseconds) } else { scalarMS.append(milliseconds) }
        }
    }
}
let report: [String: Any] = ["verificationCases": verificationCases, "scalarMS": scalarMS,
    "wordsMS": wordsMS, "checksum": scratch.reduce(UInt64(0)) { $0 + UInt64($1) }]
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
