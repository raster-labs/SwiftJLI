// Standalone Core Foundation pointer-acquisition feasibility experiment.
// No unsafe cast, unchecked Sendable annotation, or autoreleasepool is used.
import Foundation
import CoreFoundation
import Synchronization

final class CFProbeReleases: Sendable {
    let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
}

struct CFProbeBytes {
    private let owner: NSData
    private let bounds: Range<Int>

    init(_ input: Data) {
        owner = input as NSData
        bounds = 0..<input.count
    }

    private init(owner: NSData, bounds: Range<Int>) {
        self.owner = owner
        self.bounds = bounds
    }

    var count: Int { bounds.count }

    func slice(_ range: Range<Int>) -> CFProbeBytes {
        precondition(range.lowerBound >= 0 && range.upperBound <= bounds.count)
        return CFProbeBytes(owner: owner,
            bounds: (bounds.lowerBound + range.lowerBound)..<(bounds.lowerBound + range.upperBound))
    }

    var buffer: UnsafeRawBufferPointer {
        guard !bounds.isEmpty else { return .init(start: nil, count: 0) }
        return withExtendedLifetime(owner) {
            let bytes = UnsafeRawBufferPointer(start: CFDataGetBytePtr(owner as CFData),
                                              count: bounds.upperBound)
            return UnsafeRawBufferPointer(rebasing: bytes[bounds])
        }
    }

    func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try withExtendedLifetime(owner) { try body(buffer) }
    }
}

@inline(never)
func retainedCustomInput(_ releases: CFProbeReleases, seed: UInt8) -> CFProbeBytes {
    let count = 262_144
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
    pointer.initializeMemory(as: UInt8.self, repeating: seed, count: count)
    let input = Data(bytesNoCopy: pointer, count: count, deallocator: .custom { pointer, _ in
        pointer.deallocate()
        releases.count.withLock { $0 += 1 }
    })
    let expectedAddress = input.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
    let owner = CFProbeBytes(input)
    precondition(owner.withBytes { UInt(bitPattern: $0.baseAddress) } == expectedAddress)
    return owner.slice(17..<(count - 11))
}

@inline(never)
func consumeAndDropCFInput(_ releases: CFProbeReleases, seed: UInt8, previous: Int) {
    let owner = retainedCustomInput(releases, seed: seed)
    let cached = owner.buffer
    withExtendedLifetime(owner) {
        precondition(cached[0] == seed && cached[cached.count - 1] == seed)
        precondition(releases.value == previous)
    }
}

func runProbe() {
    for count in [0, 1, 15, 16, 64, 4096] {
        var input = Data(repeating: 7, count: count)
        let address = input.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        let owner = CFProbeBytes(input)
        let same = owner.withBytes { UInt(bitPattern: $0.baseAddress) } == address
        print("CFDataGetBytePtr size", count, "same input pointer", same)
        precondition(owner.withBytes { Array($0) } == Array(repeating: UInt8(7), count: count))
        if count > 0 {
            input[input.startIndex] = 9
            precondition(owner.withBytes { $0[0] } == 7)
        }
    }
    let source = Data((0..<128).map(UInt8.init))
    let shifted = source[17..<100]
    let owner = CFProbeBytes(shifted)
    let address = shifted.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
    precondition(owner.withBytes { UInt(bitPattern: $0.baseAddress) } == address)
    precondition(owner.slice(3..<8).withBytes { Array($0) } == [20, 21, 22, 23, 24])
    let mutable = NSMutableData(data: Data(repeating: 31, count: 4096))
    let snapshot = CFProbeBytes(Data(referencing: mutable))
    mutable.mutableBytes.storeBytes(of: UInt8(99), as: UInt8.self)
    precondition(snapshot.withBytes { $0[0] } == 31)
    let releases = CFProbeReleases()
    for index in 0..<32 {
        consumeAndDropCFInput(releases, seed: UInt8(index), previous: index)
        precondition(releases.value == index + 1)
    }
    print("CFDataGetBytePtr scoped owners, slices, COW and immediate releases:", releases.value, "/32")
}
runProbe()
