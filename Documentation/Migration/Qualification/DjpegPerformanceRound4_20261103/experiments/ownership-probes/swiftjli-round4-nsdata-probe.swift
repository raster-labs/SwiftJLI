// Standalone source-only ownership probe, not shipped SwiftJLI code.
// No unchecked Sendable annotation, no escaped Data.withUnsafeBytes pointer.
// Compile later in the coordinated CPU slot with Swift 6 strict concurrency.
import Foundation
import Dispatch
import Synchronization

struct NSDataWindow: RandomAccessCollection {
    typealias Index = Int
    private let owner: NSData
    private let bounds: Range<Int>

    init(_ data: Data) {
        owner = data as NSData
        bounds = 0..<data.count
    }

    private init(owner: NSData, bounds: Range<Int>) {
        self.owner = owner
        self.bounds = bounds
    }

    var startIndex: Int { 0 }
    var endIndex: Int { bounds.count }
    var ownerIsMutable: Bool { owner is NSMutableData }

    subscript(index: Int) -> UInt8 {
        precondition(index >= 0 && index < bounds.count)
        return withExtendedLifetime(owner) {
            owner.bytes.load(fromByteOffset: bounds.lowerBound + index, as: UInt8.self)
        }
    }

    func rebasedSlice(_ range: Range<Int>) -> NSDataWindow {
        precondition(range.lowerBound >= 0 && range.upperBound <= bounds.count)
        return NSDataWindow(owner: owner,
            bounds: (bounds.lowerBound + range.lowerBound)..<(bounds.lowerBound + range.upperBound))
    }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try withExtendedLifetime(owner) {
            let start = bounds.isEmpty ? nil : owner.bytes.advanced(by: bounds.lowerBound)
            return try body(UnsafeRawBufferPointer(start: start, count: bounds.count))
        }
    }

    // Identity evidence only; no raw pointer leaves the synchronous scope.
    var address: UInt {
        withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
    }
}

#if CHECK_SENDABLE
// Expected negative compile: installed NSData has no Sendable conformance.
extension NSDataWindow: Sendable {}
#endif

final class ReleaseCount: Sendable {
    let count = Mutex(0)
    func released() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

func makeNoCopyData(count: Int, release: ReleaseCount) -> Data {
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
    pointer.initializeMemory(as: UInt8.self, repeating: 29, count: count)
    return Data(bytesNoCopy: pointer, count: count, deallocator: .custom { pointer, _ in
        pointer.deallocate()
        release.released()
    })
}

func retainedWindow(release: ReleaseCount) -> NSDataWindow {
    let input = makeNoCopyData(count: 4096, release: release)
    let address = input.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
    let owner = NSDataWindow(input)
    print("large no-copy Data bridge shares bytes:", owner.address == address,
          "mutable NSData:", owner.ownerIsMutable)
    return owner.rebasedSlice(37..<4000)
}

func exerciseLifetime(release: ReleaseCount) {
    let window = retainedWindow(release: release)
    precondition(window[0] == 29 && window[window.count - 1] == 29)
    print("original allocation release count while retained:", release.value)
    #if CHECK_SENDABLE
    DispatchQueue.concurrentPerform(iterations: 3) { _ in
        precondition(window.withUnsafeBytes { $0.count } == 3963)
        precondition(window[0] == 29)
    }
    #else
    for _ in 0..<3 {
        precondition(window.withUnsafeBytes { $0.count } == 3963)
        precondition(window[0] == 29)
    }
    #endif
    withExtendedLifetime(window) {}
}

func retainedNSDataWindow(release: ReleaseCount) -> NSDataWindow {
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 16)
    pointer.initializeMemory(as: UInt8.self, repeating: 41, count: 4096)
    let original = NSData(bytesNoCopy: pointer, length: 4096, deallocator: { pointer, _ in
        pointer.deallocate()
        release.released()
    })
    let data = Data(referencing: original)
    let window = NSDataWindow(data)
    print("NSData to Data to NSData shares bytes:",
          window.address == UInt(bitPattern: original.bytes))
    return window.rebasedSlice(3..<4090)
}

func exerciseNSDataLifetime(release: ReleaseCount) {
    let window = retainedNSDataWindow(release: release)
    precondition(window[0] == 41 && window[window.count - 1] == 41)
    print("original NSData allocation release count while retained:", release.value)
    withExtendedLifetime(window) {}
}

func exerciseMutableReference() {
    let mutable = NSMutableData(data: Data(repeating: 31, count: 4096))
    var referencing = Data(referencing: mutable)
    let window = NSDataWindow(referencing)
    mutable.mutableBytes.storeBytes(of: UInt8(99), as: UInt8.self)
    precondition(referencing[referencing.startIndex] == 31 && window[0] == 31)
    referencing[referencing.startIndex] = 88
    precondition(window[0] == 31)
    print("NSMutableData-referencing Data remains an immutable snapshot; bridged mutable:", window.ownerIsMutable)
}

func runProbe() {
    for count in [0, 1, 15, 16, 64, 4096] {
        var input = Data(repeating: 7, count: count)
        let inputAddress = input.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        let window = NSDataWindow(input)
        print("size", count, "same pointer", window.address == inputAddress,
              "mutable NSData", window.ownerIsMutable)
        precondition(Array(window) == Array(repeating: UInt8(7), count: count))
        if count > 0 {
            input[input.startIndex] = 9
            precondition(window[0] == 7 && input[input.startIndex] == 9)
        }
    }
    let original = Data((0..<128).map(UInt8.init))
    let shifted = original[17..<100]
    precondition(shifted.startIndex == 17)
    let window = NSDataWindow(shifted)
    print("non-zero-origin Data slice shares bytes:", window.address ==
          original.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) + 17 })
    precondition(window[0] == 17 && window[82] == 99)
    precondition(Array(window[2..<5]) == [19, 20, 21])
    let nested = window.rebasedSlice(2..<30).rebasedSlice(3..<10)
    precondition(Array(nested) == Array(UInt8(22)...UInt8(28)))
    let release = ReleaseCount()
    autoreleasepool { exerciseLifetime(release: release) }
    precondition(release.value == 1)
    let nsRelease = ReleaseCount()
    autoreleasepool { exerciseNSDataLifetime(release: nsRelease) }
    precondition(nsRelease.value == 1)
    exerciseMutableReference()
    print("NSData scoped owner, COW, rebased slices and exactly-once release passed; Sendable qualification separate")
}
runProbe()
