import Foundation
import Darwin

struct InputFailure: Error {}
@inline(never)
func readFile(_ path: String, reserve: Bool, rawAppend: Bool) throws -> Data {
    let fd = open(path, O_RDONLY | O_NONBLOCK)
    guard fd >= 0 else { throw InputFailure() }
    defer { _ = close(fd) }
    var openedStat = stat()
    guard fstat(fd, &openedStat) == 0, (openedStat.st_mode & S_IFMT) == S_IFREG,
          openedStat.st_size >= 0, openedStat.st_size <= 64 * 1024 * 1024 else { throw InputFailure() }
    let flags = fcntl(fd, F_GETFL, 0)
    if flags >= 0 && (flags & O_NONBLOCK) != 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
    var buffer = Data()
    if reserve { buffer.reserveCapacity(Int(openedStat.st_size)) }
    let chunkSize = 64 * 1024
    var chunk = [UInt8](repeating: 0, count: chunkSize)
    while true {
        try Task.checkCancellation()
        let count = chunk.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.read(fd, base, chunkSize)
        }
        if count > 0 {
            let (newCount, overflow) = buffer.count.addingReportingOverflow(count)
            guard !overflow, newCount <= 64 * 1024 * 1024 else { throw InputFailure() }
            if rawAppend {
                chunk.withUnsafeBufferPointer { raw in
                    if let base = raw.baseAddress { buffer.append(base, count: count) }
                }
            } else {
                buffer.append(contentsOf: chunk[0..<count])
            }
        } else if count == 0 {
            break
        } else if errno != EINTR {
            throw InputFailure()
        }
    }
    return buffer
}

guard CommandLine.arguments.count == 2 else { throw InputFailure() }
let path = CommandLine.arguments[1]
let reference = try Data(contentsOf: URL(fileURLWithPath: path))
var durations = [[Double]](repeating: [], count: 4)
let names = ["slice", "reservedSlice", "raw", "reservedRaw"]
var checksum: UInt64 = 0
for iteration in 0..<25 {
    // Rotate order to spread cache/thermal position across all four variants.
    for position in 0..<4 {
        let variant = (position + iteration) % 4
        let started = ContinuousClock.now
        let result = try readFile(path, reserve: variant % 2 == 1, rawAppend: variant >= 2)
        let elapsed = started.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        precondition(result == reference)
        checksum &+= UInt64(result.count)
        if iteration >= 5 { durations[variant].append(milliseconds) }
    }
}
let report: [String: Any] = ["bytes": reference.count, "checksum": checksum,
    "milliseconds": Dictionary(uniqueKeysWithValues: zip(names, durations))]
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
