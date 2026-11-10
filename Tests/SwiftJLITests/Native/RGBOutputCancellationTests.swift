// SPDX-License-Identifier: MIT
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

@Suite struct RGBOutputCancellationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.activeProcessorCount >= 2),
          arguments: [0, 5], [Backend.scalarCPU, .accelerated])
    func interruptedFirstTileWindowDoesNotWriteCallerStorage(sourcePadding: Int, backend: Backend) throws {
        let width = 257, height = 259, sourceWidth = width + sourcePadding
        let rowBytes = width * 3 + 11, offset = 3
        let y = [Float](repeating: 127.5, count: sourceWidth * height)
        let chroma = [Float](repeating: 128, count: width * height)
        let planes = [(data: y, width: sourceWidth, height: height),
                      (data: chroma, width: width, height: height),
                      (data: chroma, width: width, height: height)]
        var destination = [UInt8](repeating: 0xA5, count: offset + height * rowBytes + 7)
        let polls = Mutex(0)
        #expect(throws: CancellationError.self) {
            try destination.withUnsafeMutableBytes { raw in
                try NativeOperation.withSynchronousCancellation({
                    let count = polls.withLock { $0 += 1; return $0 }
                    if count >= 10 { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 120,
                        backend: backend, maximumWorkers: 2)) {
                        try SharedDCTStorage.write(planes, width: width, height: height,
                            precision: 8, into: .init(
                                bytes: .init(rebasing: raw[offset..<(offset + height * rowBytes)]),
                                rowBytes: rowBytes, bytesPerSample: 1))
                    }
                }
            }
        }
        // Matching chroma extents avoid upsample work. Before the first window
        // can finish there are two caller checks, then each of two lanes checks
        // once on entry, before each of its four conversion batches, and on exit.
        // Poll10 therefore interrupts an active window after conversion begins,
        // regardless of lane scheduling, and before any caller-row scatter.
        #expect(polls.withLock { $0 } >= 10)
        #expect(destination.allSatisfy { $0 == 0xA5 })
        // The join-on-error contract is exercised separately by
        // NativeExecutionTests.failureJoinsEveryStartedWorker; sanitizer runs
        // cover these real internal buffer borrows. No sleep is used as proof
        // that work has ended or that freed storage remains untouched.
    }
}
