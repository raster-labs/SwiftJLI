// Standalone Foundation ownership experiment; not production SwiftJLI source.
import Foundation
import Synchronization

final class Releases: Sendable {
    let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
}

final class RetainedBytes {
    let bytes: NSData
    init(_ data: Data, localPool: Bool) {
        if localPool {
            bytes = autoreleasepool { data as NSData }
        } else {
            bytes = data as NSData
        }
    }
}

@inline(never)
func makeData(_ releases: Releases, seed: UInt8) -> Data {
    let count = 262_144
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
    pointer.initializeMemory(as: UInt8.self, repeating: seed, count: count)
    return Data(bytesNoCopy: pointer, count: count, deallocator: .custom { pointer, _ in
        pointer.deallocate()
        releases.count.withLock { $0 += 1 }
    })
}

@inline(never)
func makeOwner(_ releases: Releases, seed: UInt8, localPool: Bool, sourcePool: Bool,
               factoryPool: Bool) -> RetainedBytes {
    let data = sourcePool ? autoreleasepool { makeData(releases, seed: seed) } : makeData(releases, seed: seed)
    if factoryPool {
        return autoreleasepool { RetainedBytes(data, localPool: false) }
    }
    return RetainedBytes(data, localPool: localPool)
}

@inline(never)
func consumeAndDrop(_ releases: Releases, seed: UInt8, localPool: Bool, sourcePool: Bool = false,
                    factoryPool: Bool = false, accessPool: Bool = false, readBytes: Bool = true,
                    rawBufferPool: Bool = false) {
    let owner = makeOwner(releases, seed: seed, localPool: localPool, sourcePool: sourcePool,
                          factoryPool: factoryPool)
    if rawBufferPool {
        let raw = autoreleasepool {
            UnsafeRawBufferPointer(start: owner.bytes.bytes, count: 262_144)
        }
        // The pool has drained. Owner retention, not the pool, keeps this valid.
        withExtendedLifetime(owner) {
            precondition(raw[0] == seed && raw[raw.count - 1] == seed)
        }
        return
    }
    let read = {
        withExtendedLifetime(owner) {
            if readBytes {
                precondition(owner.bytes.length == 262_144)
                precondition(owner.bytes.bytes.load(as: UInt8.self) == seed)
            }
        }
    }
    if accessPool { autoreleasepool(invoking: read) } else { read() }
}

func exercise(_ title: String, localPool: Bool, sourcePool: Bool = false, factoryPool: Bool = false,
              accessPool: Bool = false, readBytes: Bool = true, rawBufferPool: Bool = false) {
    let releases = Releases()
    consumeAndDrop(releases, seed: 1, localPool: localPool, sourcePool: sourcePool, factoryPool: factoryPool,
                   accessPool: accessPool, readBytes: readBytes, rawBufferPool: rawBufferPool)
    print(title, "after one scope:", releases.value)
    for index in 1..<32 {
        consumeAndDrop(releases, seed: UInt8(index), localPool: localPool, sourcePool: sourcePool,
                       factoryPool: factoryPool, accessPool: accessPool, readBytes: readBytes,
                       rawBufferPool: rawBufferPool)
    }
    print(title, "after 32 unique allocation scopes:", releases.value)
}

exercise("ordinary bridge, no surrounding pool", localPool: false)
exercise("init-local bridge pool, no surrounding pool", localPool: true)
exercise("source creation pool, ordinary bridge", localPool: false, sourcePool: true)
exercise("source creation pool and init-local bridge pool", localPool: true, sourcePool: true)
exercise("entire Swift owner factory pool", localPool: false, factoryPool: true)
exercise("no NSData property reads", localPool: false, readBytes: false)
exercise("pool only around NSData property reads", localPool: false, accessPool: true)
exercise("factory pool and NSData property read pool", localPool: false, factoryPool: true, accessPool: true)
exercise("pool around buffer construction, raw loads after drain", localPool: false, rawBufferPool: true)

@inline(never)
func createAndDropData(_ releases: Releases, sourcePool: Bool) {
    let data = sourcePool ? autoreleasepool { makeData(releases, seed: 3) } : makeData(releases, seed: 3)
    precondition(data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in bytes[0] } == 3)
}
for sourcePool in [false, true] {
    let releases = Releases()
    for _ in 0..<32 { createAndDropData(releases, sourcePool: sourcePool) }
    print("Data-only control, source pool", sourcePool, "releases:", releases.value)
}
let controlled = Releases()
autoreleasepool {
    for index in 0..<32 {
        consumeAndDrop(controlled, seed: UInt8(index), localPool: false)
    }
    print("control ordinary bridge, inside explicit pool:", controlled.value)
}
print("control ordinary bridge, after explicit pool drains:", controlled.value)
