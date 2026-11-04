// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
// Internal pointer views never escape a synchronous call; no Sendable assertion.
struct QualifiedStorageArray<Element>: RandomAccessCollection {
    typealias Index = Int
    private let borrowed: UnsafeMutableBufferPointer<Element>
    private(set) var count = 0
    init(borrowing buffer: UnsafeMutableBufferPointer<Element>) { borrowed = buffer }
    var startIndex: Int { 0 }; var endIndex: Int { count }
    subscript(index: Int) -> Element { borrowed[index] }
    mutating func append(_ element: Element) {
        precondition(count < borrowed.count)
        borrowed.baseAddress!.advanced(by: count).initialize(to: element)
        count += 1
    }
}
typealias QualifiedScanComponent = (componentSelector: UInt8, dcTableId: Int, acTableId: Int)
struct QualifiedByteView: RandomAccessCollection {
    let borrowed: UnsafeRawBufferPointer
    init(borrowing bytes: UnsafeRawBufferPointer) { borrowed = bytes }
    var startIndex: Int { 0 }; var endIndex: Int { borrowed.count }
    subscript(index: Int) -> UInt8 { borrowed[index] }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R { body(borrowed) }
}
internal struct QualifiedCallerRecords {
    static let byteCount = 4096
    private let frame: UnsafeMutableBufferPointer<QualifiedComponentInfo>
    private let components: UnsafeMutableBufferPointer<QualifiedScanComponent>
    private let scans: UnsafeMutableBufferPointer<QualifiedScanData>
    private let counts: UnsafeMutableBufferPointer<Int>
    init(_ bytes: UnsafeMutableRawBufferPointer) {
        precondition(bytes.count >= Self.byteCount)
        var offset = 0
        func buffer<T>(_ type: T.Type, _ n: Int) -> UnsafeMutableBufferPointer<T> {
            let alignment = MemoryLayout<T>.alignment
            offset = (offset + alignment - 1) & ~(alignment - 1)
            let start = offset; offset += MemoryLayout<T>.stride * n
            precondition(offset <= Self.byteCount)
            return UnsafeMutableRawBufferPointer(rebasing: bytes[start..<offset]).bindMemory(to: T.self)
        }
        frame = buffer(QualifiedComponentInfo.self, 3)
        components = buffer(QualifiedScanComponent.self, 9)
        scans = buffer(QualifiedScanData.self, 3)
        counts = buffer(Int.self, 3); counts.initialize(repeating: 0)
    }
    func frameStorage() -> QualifiedStorageArray<QualifiedComponentInfo> { QualifiedStorageArray(borrowing: frame) }
    func componentStorage() -> QualifiedStorageArray<QualifiedScanComponent> {
        let index = counts[1]
        precondition(index < 3)
        counts[1] += 1
        return QualifiedStorageArray(borrowing: UnsafeMutableBufferPointer(rebasing: components[(index * 3)..<(index * 3 + 3)]))
    }
    func scanStorage() -> QualifiedStorageArray<QualifiedScanData> { QualifiedStorageArray(borrowing: scans) }
    func didAppendScan() { counts[2] += 1 }
    func destroy() { scans.baseAddress!.deinitialize(count: counts[2]); counts[2] = 0 }
}
internal struct QualifiedTriple<Element>: RandomAccessCollection {
    private var a: Element, b: Element, c: Element
    init(_ value: (Int) -> Element) { a = value(0); b = value(1); c = value(2) }
    var startIndex: Int { 0 }; var endIndex: Int { 3 }
    subscript(index: Int) -> Element {
        get { switch index { case 0: return a; case 1: return b; case 2: return c; default: preconditionFailure() } }
        set { switch index { case 0: a = newValue; case 1: b = newValue; case 2: c = newValue; default: preconditionFailure() } }
    }
}
