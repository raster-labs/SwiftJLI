// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization

/// One joined reconstruction worker overlaps serial entropy decoding. The caller
/// alone reads compressed input and writes provider storage. Two internal slots
/// alternate, each holding a 256-block FMA or 1024-block GEMM coefficient/output
/// batch. Admission and dispatch use the same immutable batch size.
enum PipelinedGreyscaleDecoder {
    private final class State: Sendable {
        struct Progress {
            var published = 0
            var completed = 0
            var workerWaiting = false
            var producerWaiting = false
            var stopped = false
            var error: (any Error)?
        }
        let published = Atomic<Int>(0)
        let workerParked = Atomic<Bool>(false)
        let completed = Atomic<Int>(0)
        let producerParked = Atomic<Bool>(false)
        let stopped = Atomic<Bool>(false)
        let progress = Mutex(Progress())
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let joined = DispatchGroup()
    }

    /// These independently owned arrays remain borrowed until joined.wait()
    /// returns, on every success/error path. Entropy exclusively owns slot N
    /// until signalling ready; the worker owns it through reconstruction and
    /// compaction, then publishes completion under the mutex. Only after that
    /// publication may the caller scatter/reuse the slot. The worker alone uses
    /// optional GEMM scratch; block-local reconstruction owns only local values.
    /// The quantiser is immutable. No provider pointer is captured.
    private struct Buffers: @unchecked Sendable {
        let coefficients: UnsafeMutablePointer<Int32>
        let scratch: UnsafeMutablePointer<Float>?
        let quantiser: UnsafePointer<Float>
    }

    static func decode(reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
                       lookup: ACLookahead?, quantTable: [Float], plan: SequentialGreyscalePlan,
                       width: Int, height: Int, precision: Int, restartInterval: Int,
                       floatOutput: Bool, destination: BorrowedSampleDestination) throws {
        let blocks = plan.blockCount, batchBlocks = plan.batchBlocks
        guard blocks >= 2048, blocks <= Int.max / 64,
              batchBlocks == 1024 || (plan.blockLocalIDCT && batchBlocks == 256),
              plan.blocksPerRow > 0,
              precision == 8 || precision == 12, restartInterval >= 0,
              quantTable.count >= 64 else {
            throw JLIError.decodingFailed("Invalid pipelined greyscale scan")
        }
        let slotSamples = batchBlocks * 64
        var coefficients = [Int32](unsafeUninitializedCapacity: slotSamples * 2) { _, count in count = slotSamples * 2 }
        let scratchCount = plan.blockLocalIDCT ? 0 : slotSamples
        // A zero-capacity uninitialised constructor writes the shared empty
        // Array storage on this toolchain. FMA needs no scratch or such write.
        var scratch: [Float] = scratchCount == 0 ? [] :
            [Float](unsafeUninitializedCapacity: scratchCount) { _, count in count = scratchCount }
        try coefficients.withUnsafeMutableBufferPointer { cp in
            try scratch.withUnsafeMutableBufferPointer { sp in
                try quantTable.withUnsafeBufferPointer { qt in
                    guard let base = cp.baseAddress,
                          plan.blockLocalIDCT || sp.baseAddress != nil,
                          let quantiser = qt.baseAddress else {
                        throw JLIError.decodingFailed("Missing pipeline storage")
                    }
                    let buffers = Buffers(coefficients: base, scratch: sp.baseAddress, quantiser: quantiser)
                    let state = State(), batches = (blocks - 1) / batchBlocks + 1
                    let context = NativeOperation.current, bps = destination.bytesPerSample
                    // The group covers the entire submitted work item, rather
                    // than an early signal from inside the worker body.
                    DispatchQueue.global(qos: .userInitiated).async(group: state.joined) {
                        do {
                            try NativeOperation.$current.withValue(context) {
                                for batch in 0..<batches {
                                    var spin = 0
                                    while state.published.load(ordering: .acquiring) <= batch {
                                        if state.stopped.load(ordering: .acquiring) { return }
                                        if spin < 4096 {
                                            spin &+= 1
                                            var delay = spin
                                            for _ in 0..<64 { delay = delay &* 1664525 &+ 1013904223 }
                                            if delay == -1 { _ = state.published.load(ordering: .relaxed) }
                                            continue
                                        }
                                        state.workerParked.store(true, ordering: .sequentiallyConsistent)
                                        if state.stopped.load(ordering: .sequentiallyConsistent) {
                                            state.workerParked.store(false, ordering: .releasing)
                                            return
                                        }
                                        if state.published.load(ordering: .sequentiallyConsistent) > batch {
                                            state.workerParked.store(false, ordering: .releasing)
                                            break
                                        }
                                        state.ready.wait()
                                    }
                                    if state.stopped.load(ordering: .acquiring) { return }
                                    try NativeOperation.check()
                                    let count = min(batchBlocks, blocks - batch * batchBlocks) * 64
                                    try ParallelSequentialGreyscaleDecoder.reconstructWindow(
                                        .init(start: buffers.coefficients + (batch & 1) * slotSamples, count: count),
                                        quantTable: .init(start: buffers.quantiser, count: 64),
                                        scratch: .init(start: buffers.scratch, count: scratchCount),
                                        precision: precision, bytesPerSample: bps, floatOutput: floatOutput)
                                    state.completed.store(batch + 1, ordering: .sequentiallyConsistent)
                                    if state.producerParked.load(ordering: .sequentiallyConsistent) {
                                        if state.producerParked.exchange(false, ordering: .acquiringAndReleasing) {
                                            state.done.signal()
                                        }
                                    }
                                }
                            }
                        } catch {
                            state.progress.withLock { progress in
                                progress.error = error
                                progress.stopped = true
                            }
                            state.stopped.store(true, ordering: .sequentiallyConsistent)
                            if state.producerParked.exchange(false, ordering: .acquiringAndReleasing) {
                                state.done.signal()
                            }
                        }
                    }
                    // Wake a worker waiting for unpublished entropy on any
                    // producer error, then join before either array borrow ends.
                    defer {
                        state.stopped.store(true, ordering: .sequentiallyConsistent)
                        if state.workerParked.exchange(false, ordering: .acquiringAndReleasing) {
                            state.ready.signal()
                        }
                        state.joined.wait()
                    }
                    func scatterCompleted(_ batch: Int) throws {
                        while state.completed.load(ordering: .acquiring) <= batch {
                            if state.stopped.load(ordering: .acquiring) {
                                if let error = state.progress.withLock({ $0.error }) { throw error }
                            }
                            state.producerParked.store(true, ordering: .sequentiallyConsistent)
                            if state.stopped.load(ordering: .sequentiallyConsistent) {
                                state.producerParked.store(false, ordering: .releasing)
                                if let error = state.progress.withLock({ $0.error }) { throw error }
                            }
                            if state.completed.load(ordering: .sequentiallyConsistent) > batch {
                                state.producerParked.store(false, ordering: .releasing)
                                break
                            }
                            try NativeOperation.check()
                            // Deadline/cancellation remains observable while
                            // the bounded reconstruction unit is in flight.
                            _ = state.done.wait(timeout: .now() + .milliseconds(5))
                        }
                        if state.stopped.load(ordering: .acquiring) {
                            if let error = state.progress.withLock({ $0.error }) { throw error }
                        }
                        try NativeOperation.check()
                        let count = min(batchBlocks, blocks - batch * batchBlocks) * 64
                        try ParallelSequentialGreyscaleDecoder.scatterWindow(
                            .init(start: base + (batch & 1) * slotSamples, count: count),
                            firstBlock: batch * batchBlocks, blocksPerRow: plan.blocksPerRow,
                            width: width, height: height, destination: destination)
                    }
                    try CDCTKernel.withBorrowed(dcTable: dcTable, acTable: acTable, lookup: lookup,
                        enabled: NativeOperation.current?.backend == .accelerated) { kernel in
                        var previousDC: Int32 = 0, restartIndex = 0
                        for batch in 0..<batches {
                            if batch >= 2 { try scatterCompleted(batch - 2) }
                            if state.stopped.load(ordering: .acquiring) {
                                if let error = state.progress.withLock({ $0.error }) { throw error }
                            }
                            let first = batch * batchBlocks, end = min(first + batchBlocks, blocks)
                            let slot = base + (batch & 1) * slotSamples
                            var index = first
                            while index < end {
                                try NativeOperation.check()
                                let rowEnd = min(end, index + plan.blocksPerRow - index % plan.blocksPerRow)
                                while index < rowEnd {
                                    if restartInterval > 0, index > 0, index % restartInterval == 0 {
                                        try reader.skipRestartMarker(expectedIndex: restartIndex)
                                        restartIndex = (restartIndex + 1) & 7
                                        previousDC = 0
                                    }
                                    if let kernel {
                                        let spanEnd: Int
                                        if restartInterval > 0 {
                                            let nextRestart = index + restartInterval - (index % restartInterval)
                                            spanEnd = min(rowEnd, nextRestart)
                                        } else {
                                            spanEnd = rowEnd
                                        }
                                        let count = spanEnd - index
                                        let span = UnsafeMutableBufferPointer(start: slot + (index - first) * 64, count: count * 64)
                                        try reader.decodeDCTRun(using: kernel, previousDC: &previousDC,
                                                                precision: precision, blockCount: count, into: span)
                                        index = spanEnd
                                    } else {
                                        let block = UnsafeMutableBufferPointer(start: slot + (index - first) * 64, count: 64)
                                        let difference = try HuffmanDecoder.decodeDC(from: &reader, table: dcTable)
                                        let dc = Int64(previousDC) + Int64(difference)
                                        guard abs(dc) <= (1 << (precision + 2)) else {
                                            throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
                                        }
                                        previousDC = Int32(dc)
                                        if let lookup {
                                            try HuffmanDecoder.decodeAC(from: &reader, table: acTable, lookup: lookup, into: block)
                                        } else {
                                            try HuffmanDecoder.decodeAC(from: &reader, table: acTable, into: block)
                                        }
                                        block[0] = previousDC
                                        index += 1
                                    }
                                }
                            }
                            state.published.store(batch + 1, ordering: .sequentiallyConsistent)
                            if state.workerParked.load(ordering: .sequentiallyConsistent) {
                                if state.workerParked.exchange(false, ordering: .acquiringAndReleasing) {
                                    state.ready.signal()
                                }
                            }
                        }
                    }
                    for batch in max(0, batches - 2)..<batches { try scatterCompleted(batch) }
                }
            }
        }
    }
}
