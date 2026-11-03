// SPDX-License-Identifier: Apache-2.0

/// Shared admission and dispatch decision for bounded sequential reconstruction.
/// A plan exists only when the decoder will avoid its full coefficient/Float
/// planes. Resource admission must not infer streaming from geometry alone.
struct SequentialGreyscalePlan: Sendable {
    static let maximumBatchBlocks = 1024
    static let maximumParallelLanes = 8
    static let maximumWindowBlocks = maximumBatchBlocks * maximumParallelLanes
    static let maximumAutomaticBlocks = 4096
    static let maximumAutomaticScalarBlocks = 2048

    let blocksPerRow: Int
    let blockRows: Int
    let blockCount: Int
    let batchBlocks: Int
    let parallelLanes: Int
    /// Payload of one Int32 coefficient/output batch and one Float IDCT scratch.
    /// This is a conservative reservation component, not measured peak memory.
    let workspaceBytes: Int

    /// `workerLimit` and `backend` are the immutable operation choices used by
    /// both admission and dispatch. Actual joined work may clamp the worker
    /// ceiling to currently active CPUs.
    /// Re-reading a changing CPU count here could otherwise select different
    /// allocation paths before and after admission.
    static func make(parsed: ParsedJPEG, configuration: JLIDecoderConfiguration,
                     hasDestination: Bool, normaliseXYBOutput: Bool,
                     workerLimit: Int, backend: Backend) throws -> Self? {
        let frame = parsed.frameInfo
        guard MemoryLayout<Int32>.stride == MemoryLayout<Float>.stride,
              MemoryLayout<Int32>.alignment >= MemoryLayout<Float>.alignment,
              hasDestination, !frame.isLossless, !frame.isProgressive,
              configuration.scale == 1, frame.components.count == 1,
              parsed.scans.count == 1,
              frame.components[0].horizontalSampling == 1,
              frame.components[0].verticalSampling == 1,
              frame.precision == 8 || frame.precision == 12,
              frame.width > 0, frame.height > 0, workerLimit > 0,
              !parsed.isXYB, !parsed.isRawRGB, !normaliseXYBOutput,
              configuration.outputColorModel == nil,
              configuration.outputPixelFormat == nil || configuration.outputPixelFormat == .float32 else {
            return nil
        }
        let blocksPerRow = try checkedAdd(frame.width, 7) / 8
        let blockRows = try checkedAdd(frame.height, 7) / 8
        let blockCount = try checkedMultiply(blocksPerRow, blockRows)
        // Small images retain their measured serial path. A large window uses
        // whole canonical transforms and never exceeds eight logical lanes.
        // A changing active-CPU count may execute fewer lanes, but cannot change
        // this allocation/admission decision based on the immutable ceiling.
        let serialThreshold = backend == .accelerated ? maximumAutomaticBlocks : maximumAutomaticScalarBlocks
        let parallelLanes: Int
        if workerLimit == 1 || blockCount <= serialThreshold { parallelLanes = 1 }
        else {
            parallelLanes = min(maximumParallelLanes, min(workerLimit, blockCount / 2048))
            guard parallelLanes > 1 else { return nil }
        }
        let batchBlocks = min(try checkedMultiply(maximumBatchBlocks, parallelLanes), blockCount)
        let samples = try checkedMultiply(batchBlocks, 64)
        let bytesPerSample = try checkedAdd(MemoryLayout<Int32>.stride, MemoryLayout<Float>.stride)
        let workspaceBytes = try checkedMultiply(samples, bytesPerSample)
        return Self(blocksPerRow: blocksPerRow, blockRows: blockRows,
                    blockCount: blockCount, batchBlocks: batchBlocks,
                    parallelLanes: parallelLanes, workspaceBytes: workspaceBytes)
    }
}
