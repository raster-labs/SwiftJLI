// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftJLI

@Suite struct PipelinedGreyscaleTests {
    private func fixture(width: Int, precision: Int) throws -> ParsedJPEG {
        let height = 257, bps = precision == 8 ? 1 : 2
        var samples = [UInt8](repeating: 0, count: width * height * bps)
        for i in 0..<(width * height) {
            let value = (i * 151 + i / width * 17 + 117) & ((1 << precision) - 1)
            samples[i * bps] = UInt8(truncatingIfNeeded: value)
            if bps == 2 { samples[i * bps + 1] = UInt8(value >> 8) }
        }
        let image = try JLIImage(width: width, height: height,
            pixelFormat: precision == 8 ? .uint8 : .uint16, colorModel: .grayscale, data: samples)
        var parser = MarkerReader(data: try JLIEncoder().encode(image,
            configuration: .init(quality: 87, restartInterval: 1023)))
        return try parser.parse()
    }

    @Test(arguments: [8, 12], [false, true])
    func alternatingSlotsPreserveCanonicalBitsRestartsAndOddPadding(precision: Int, floating: Bool) throws {
        for width in [513, 1025] {
            let parsed = try fixture(width: width, precision: precision), height = 257
            let cfg = JLIDecoderConfiguration(outputPixelFormat: floating ? .float32 : nil)
            let bps = floating ? 4 : precision == 8 ? 1 : 2, stride = width * bps + 11
            let expected = try NativeOperation.$current.withValue(.init(seconds: 120,
                backend: .accelerated, maximumWorkers: 1)) {
                try JLIDecoder().decodeParsed(parsed, configuration: cfg).data
            }
            for workers in [2, 8] {
                let plan = try #require(try SequentialGreyscalePlan.make(parsed: parsed, configuration: cfg,
                    hasDestination: true, normaliseXYBOutput: false, workerLimit: workers, backend: .accelerated))
                #expect(plan.pipelined && plan.workspaceBytes == (BlockLocalIDCT.available ? 131_072 : 786_432))
                #expect(plan.batchBlocks == (BlockLocalIDCT.available ? 256 : 1024))
                var output = [UInt8](repeating: 0xA5, count: 3 + stride * height + 7)
                try NativeOperation.$current.withValue(.init(seconds: 120, backend: .accelerated, maximumWorkers: workers)) {
                    try output.withUnsafeMutableBytes { bytes in
                        _ = try JLIDecoder().decodeParsed(parsed, configuration: cfg,
                            borrowedDestination: .init(bytes: .init(rebasing: bytes[3..<(3 + stride * height)]),
                                rowBytes: stride, bytesPerSample: bps))
                    }
                }
                #expect(output.prefix(3).allSatisfy { $0 == 0xA5 } && output.suffix(7).allSatisfy { $0 == 0xA5 })
                for row in 0..<height {
                    let first = 3 + row * stride, count = width * bps
                    #expect(output[first..<(first + count)].elementsEqual(expected[(row * count)..<((row + 1) * count)]))
                    #expect(output[(first + count)..<(first + stride)].allSatisfy { $0 == 0xA5 })
                }
            }
        }
    }

    @Test(arguments: [Backend.scalarCPU, .accelerated])
    func producerCancellationAndWorkerFailureJoinBeforeReturning(backend: Backend) throws {
        let parsed = try fixture(width: 513, precision: 8), scan = parsed.scans[0]
        let acceleratedPlan = try #require(try SequentialGreyscalePlan.make(parsed: parsed, configuration: .default,
            hasDestination: true, normaliseXYBOutput: false, workerLimit: 2, backend: .accelerated))
        // This deliberately private scalar pipeline invocation is outside the
        // public scalar admission path. Supply its actual GEMM scratch while
        // retaining the same joined worker, cancellation and caller canaries.
        let plan = backend == .scalarCPU ? SequentialGreyscalePlan(
            blocksPerRow: acceleratedPlan.blocksPerRow, blockRows: acceleratedPlan.blockRows,
            blockCount: acceleratedPlan.blockCount, batchBlocks: 1024,
            parallelLanes: acceleratedPlan.parallelLanes, pipelined: acceleratedPlan.pipelined,
            blockLocalIDCT: false, dcOnlyTable: acceleratedPlan.dcOnlyTable, workspaceBytes: 786_432)
            : acceleratedPlan
        let selector = try #require(scan.header.components.first)
        let dc = try #require(scan.dcTables[selector.dcTableId]), ac = try #require(scan.acTables[selector.acTableId])
        for failWorker in [false, true] {
            let polls = Mutex(0)
            // An unsupported internal sample layout fails inside the worker
            // on every backend. NaN quantisers are not public JPEG inputs, and
            // scalar and Accelerate clipping can differ for NaN.
            let bytesPerSample = failWorker ? 3 : 1
            var output = [UInt8](repeating: 0xA5, count: 513 * 257 * bytesPerSample)
            var reader = BitReader(data: scan.entropyData)
            let result = Result {
                try NativeOperation.withSynchronousCancellation({
                    let n = polls.withLock { $0 += 1; return $0 }
                    if !failWorker && n >= 5 { throw CancellationError() }
                }) {
                    try NativeOperation.$current.withValue(.init(seconds: 120, backend: backend, maximumWorkers: 2)) {
                        try output.withUnsafeMutableBytes { bytes in
                            try PipelinedGreyscaleDecoder.decode(reader: &reader, dcTable: dc, acTable: ac,
                                lookup: ACLookahead(table: ac, blockCount: plan.blockCount),
                                quantTable: [Float](repeating: 1, count: 64), plan: plan,
                                width: 513, height: 257, precision: 8, restartInterval: parsed.restartInterval,
                                floatOutput: false, destination: .init(bytes: bytes,
                                    rowBytes: 513 * bytesPerSample, bytesPerSample: bytesPerSample))
                        }
                    }
                }
            }
            switch result {
            case .success: Issue.record("Failed pipeline published a successful image")
            case .failure(let error): #expect(failWorker ? error is JLIError : error is CancellationError)
            }
            #expect(output.allSatisfy { $0 == 0xA5 })
            // Immediate reuse after the joined failure is covered by ASan/TSan;
            // no timing delay is used as evidence of worker completion.
            output.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 7) }
            #expect(output.allSatisfy { $0 == 7 })
        }
    }
}
