// Standalone ownership feasibility probe; not shipped SwiftJLI source.
// Compile with Swift 6 mode, strict concurrency, OS 26 target, no feature flags.
import Foundation
import Dispatch

#if OWNED_ENUM_PROBE
enum ProbeReaderBytes: ~Escapable {
    case owned([UInt8])
    case borrowed(Span<UInt8>)

    var count: Int {
        switch self {
        case .owned(let bytes): bytes.count
        case .borrowed(let bytes): bytes.count
        }
    }

    subscript(index: Int) -> UInt8 {
        switch self {
        case .owned(let bytes): bytes[index]
        case .borrowed(let bytes): bytes[index]
        }
    }

    func loadWord(at offset: Int) -> UInt64 {
        switch self {
        case .owned(let bytes):
            return bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        case .borrowed(let bytes):
            return bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        }
    }
}
#else
// Preferred production shape: one span, no representation branch per byte.
struct ProbeReader: ~Escapable, ~Copyable {
    private let bytes: Span<UInt8>
    private(set) var offset = 0

    @lifetime(borrow data)
    init(data: borrowing [UInt8]) {
        bytes = data.span
    }

    @lifetime(borrow data)
    init(borrowing data: borrowing [UInt8]) {
        bytes = data.span
    }

    @lifetime(copy span)
    init(span: Span<UInt8>) {
        bytes = span
    }

    mutating func read() -> UInt8 {
        precondition(offset < bytes.count)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readWord() -> UInt64 {
        precondition(bytes.count - offset >= 8)
        defer { offset += 8 }
        return bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }
}
#endif

#if OWNED_ENUM_PROBE
struct ProbeReader: ~Escapable {
    private let bytes: ProbeReaderBytes
    private(set) var offset = 0

    // No borrowed storage exists in this representation. The array is owned.
    @lifetime(immortal)
    init(data: [UInt8]) {
        bytes = .owned(data)
    }

    init(borrowing data: borrowing [UInt8]) {
        bytes = .borrowed(data.span)
    }

    init(span: Span<UInt8>) {
        bytes = .borrowed(span)
    }

    mutating func read() -> UInt8 {
        precondition(offset < bytes.count)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readWord() -> UInt64 {
        precondition(bytes.count - offset >= 8)
        defer { offset += 8 }
        return bytes.loadWord(at: offset)
    }
}
#endif

// Result deliberately remains Escapable. Returning a reader is forbidden.
func withProbeReader<Result>(_ data: Data,
                             _ body: (inout ProbeReader) throws -> Result) rethrows -> Result {
    try data.withUnsafeBytes { raw in
        let span = Span<UInt8>(_unsafeBytes: raw)
        var reader = ProbeReader(span: span)
        return try body(&reader)
    }
}

func sum(_ reader: inout ProbeReader) -> Int {
    Int(reader.read()) + Int(reader.read())
}

func nestedDecode(_ reader: inout ProbeReader) -> Int {
    var output = [UInt8](repeating: 0, count: 2)
    output.withUnsafeMutableBufferPointer { destination in
        destination[0] = reader.read()
        destination[1] = reader.read()
    }
    return Int(output[0]) + Int(output[1])
}

#if NEGATIVE_RETURN
// Must fail: the helper result would retain a borrow past its scoped callback.
func forbiddenReturn(_ data: borrowing Data) -> ProbeReader {
    withProbeReader(data) { reader in reader }
}
#endif

#if NEGATIVE_LOCAL_ARRAY
// Must fail: the returned reader depends on a local array lifetime.
@lifetime(immortal)
func forbiddenLocalArray() -> ProbeReader {
    let bytes: [UInt8] = [1, 2, 3]
    return ProbeReader(borrowing: bytes)
}
#endif

#if NEGATIVE_ESCAPING_CAPTURE
// Must fail: an escaping closure cannot retain the borrowed reader.
func forbiddenClosure(_ data: Data) -> () -> UInt8 {
    withProbeReader(data) { reader in
        var copy = reader
        return { copy.read() }
    }
}
#endif

func runProbe() {
    let bytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    let data = Data(bytes)
    var owning = ProbeReader(data: bytes)
    precondition(sum(&owning) == 3)
    var borrowing = ProbeReader(borrowing: bytes)
    precondition(nestedDecode(&borrowing) == 3)
    let directSpan = data.span
    var direct = ProbeReader(span: directSpan)
    precondition(sum(&direct) == 3)
    precondition(withProbeReader(data, nestedDecode) == 3)
    precondition(withProbeReader(data) { $0.readWord() } == UInt64(littleEndian: 0x0807060504030201))

    // Every worker retains/captures an immutable owner and starts a fresh local
    // borrow. No parent raw pointer or non-escapable reader crosses the boundary.
    DispatchQueue.concurrentPerform(iterations: 2) { _ in
        precondition(withProbeReader(data) { sum(&$0) } == 3)
    }
    print("Span array/Data reader, inout helpers, nested closure and joined owner capture passed")
}
runProbe()
