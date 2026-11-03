// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization

/// One joined reconstruction worker overlaps serial entropy decoding. The caller
/// alone reads compressed input and writes provider storage. Two internal slots
/// alternate, each holding one canonical 1024-block coefficient/output batch.
enum PipelinedGreyscaleDecoder {
    private final class State: Sendable {
        struct Progress { var completed = 0; var stopped = false; var error: (any Error)? }
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
    /// scratch; the quantiser is immutable. No provider pointer is captured.
    private struct Buffers: @unchecked Sendable {
        let coefficients: UnsafeMutablePointer<Int32>
        let scratch: UnsafeMutablePointer<Float>
        let quantiser: UnsafePointer<Float>
    }

    static func decode(reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable,
                       lookup: ACLookahead?, quantTable: [Float], plan: SequentialGreyscalePlan,
                       width: Int, height: Int, precision: Int, restartInterval: Int,
                       floatOutput: Bool, destination: BorrowedSampleDestination) throws {
        let blocks = plan.blockCount, slotSamples = 1024 * 64
        guard blocks >= 2048, plan.batchBlocks == 1024, plan.blocksPerRow > 0,
              precision == 8 || precision == 12, restartInterval >= 0,
              quantTable.count >= 64 else {
            throw JLIError.decodingFailed("Invalid pipelined greyscale scan")
        }
        var coefficients = [Int32](unsafeUninitializedCapacity: slotSamples * 2) { _, count in count = slotSamples * 2 }
        var scratch = [Float](unsafeUninitializedCapacity: slotSamples) { _, count in count = slotSamples }
        try coefficients.withUnsafeMutableBufferPointer { cp in
            try scratch.withUnsafeMutableBufferPointer { sp in
                try quantTable.withUnsafeBufferPointer { qt in
                    guard let base = cp.baseAddress, let workspace = sp.baseAddress,
                          let quantiser = qt.baseAddress else {
                        throw JLIError.decodingFailed("Missing pipeline storage")
                    }
                    let buffers = Buffers(coefficients: base, scratch: workspace, quantiser: quantiser)
                    let state = State(), batches = (blocks - 1) / 1024 + 1
                    let context = NativeOperation.current, bps = destination.bytesPerSample
                    // The group covers the entire submitted work item, rather
                    // than an early signal from inside the worker body.
                    DispatchQueue.global(qos: .userInitiated).async(group: state.joined) {
                        do {
                            try NativeOperation.$current.withValue(context) {
                                for batch in 0..<batches {
                                    state.ready.wait()
                                    if state.progress.withLock({ $0.stopped }) { return }
                                    try NativeOperation.check()
                                    let count = min(1024, blocks - batch * 1024) * 64
                                    try ParallelSequentialGreyscaleDecoder.reconstructWindow(
                                        .init(start: buffers.coefficients + (batch & 1) * slotSamples, count: count),
                                        quantTable: .init(start: buffers.quantiser, count: 64),
                                        scratch: .init(start: buffers.scratch, count: slotSamples),
                                        precision: precision, bytesPerSample: bps, floatOutput: floatOutput)
                                    state.progress.withLock { $0.completed = batch + 1 }
                                    state.done.signal()
                                }
                            }
                        } catch {
                            state.progress.withLock { $0.error = error; $0.stopped = true }
                            state.done.signal()
                        }
                    }
                    // Wake a worker waiting for unpublished entropy on any
                    // producer error, then join before either array borrow ends.
                    defer {
                        state.progress.withLock { $0.stopped = true }
                        state.ready.signal()
                        state.joined.wait()
                    }
                    func scatterCompleted(_ batch: Int) throws {
                        while true {
                            let status = state.progress.withLock { ($0.completed, $0.error) }
                            if let error = status.1 { throw error }
                            if status.0 > batch { break }
                            try NativeOperation.check()
                            // Deadline/cancellation remains observable while
                            // the bounded reconstruction unit is in flight.
                            _ = state.done.wait(timeout: .now() + .milliseconds(5))
                        }
                        try NativeOperation.check()
                        let count = min(1024, blocks - batch * 1024) * 64
                        try ParallelSequentialGreyscaleDecoder.scatterWindow(
                            .init(start: base + (batch & 1) * slotSamples, count: count),
                            firstBlock: batch * 1024, blocksPerRow: plan.blocksPerRow,
                            width: width, height: height, destination: destination)
                    }
                    var previousDC: Int32 = 0, restartIndex = 0
                    for batch in 0..<batches {
                        if batch >= 2 { try scatterCompleted(batch - 2) }
                        if let error = state.progress.withLock({ $0.error }) { throw error }
                        let first = batch * 1024, end = min(first + 1024, blocks)
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
                                let difference = try HuffmanDecoder.decodeDC(from: &reader, table: dcTable)
                                let dc = Int64(previousDC) + Int64(difference)
                                guard abs(dc) <= (1 << (precision + 2)) else {
                                    throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
                                }
                                previousDC = Int32(dc)
                                let block = UnsafeMutableBufferPointer(start: slot + (index - first) * 64, count: 64)
                                if let lookup {
                                    try HuffmanDecoder.decodeAC(from: &reader, table: acTable, lookup: lookup, into: block)
                                } else {
                                    try HuffmanDecoder.decodeAC(from: &reader, table: acTable, into: block)
                                }
                                block[0] = previousDC
                                index += 1
                            }
                        }
                        state.ready.signal()
                    }
                    for batch in max(0, batches - 2)..<batches { try scatterCompleted(batch) }
                }
            }
        }
    }
}
