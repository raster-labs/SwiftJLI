// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Raster Images Private Limited

/// Specialised synchronous caller-storage JPEG decoder. This API preserves the
/// managed JLISwift 0.6.0 profile at b6df774a3c3ecdf4b98971f31543fdd18074ace2.
/// Prefer the common owning Decoder for general use. The common async operation
/// cannot express a borrowed worker, scalar failures and caller-admitted arena.
///
/// Calls remain on the calling worker. Input, exclusive workspace and output must
/// stay alive and disjoint until return; no pointer escapes or task is created.
/// The zero-allocation qualification applies to the recorded optimised Release
/// build; Debug builds are not allocation-qualified. Caller storage owns payload
/// and control records. Ancillary metadata is scanned
/// in place, not returned. Discard all output on failure. This profile retains its
/// predecessor's missing-Huffman defaults and accepted restart-number policy.
/// It does not promise general JPEG conformance or automatic DICOM interpretation.
public struct QualifiedJPEGDecoder: Sendable {
    public enum Profile: Sendable { case jliswift060 }
    public enum SourceColourModel: Sendable { case rgb, yCbCr }
    /// Independent ceilings. maximumDecodedBytes bounds published logical samples.
    /// Memory counts complete supplied encoded, workspace
    /// and output capacities, including the full baseline arena rather than 3N RGB.
    public struct Limits: Sendable, Equatable {
        public let maximumEncodedBytes: Int, maximumPixels: Int, maximumDecodedBytes: Int
        public let maximumDimension: Int, maximumWorkspaceBytes: Int, maximumMemoryBytes: Int
        public let deadlineSeconds: Double
        public init(maximumEncodedBytes: Int = 64 << 20, maximumPixels: Int = 16 << 20,
                    maximumDecodedBytes: Int = 64 << 20, maximumDimension: Int = 65_535,
                    maximumWorkspaceBytes: Int = 512 << 20, maximumMemoryBytes: Int = 1 << 30,
                    deadlineSeconds: Double = 120) {
            self.maximumEncodedBytes = maximumEncodedBytes; self.maximumPixels = maximumPixels
            self.maximumDecodedBytes = maximumDecodedBytes; self.maximumDimension = maximumDimension
            self.maximumWorkspaceBytes = maximumWorkspaceBytes; self.maximumMemoryBytes = maximumMemoryBytes
            self.deadlineSeconds = deadlineSeconds
        }
    }
    private let limits: Limits
    private let sourceColourModel: SourceColourModel?
    public init(profile: Profile, limits: Limits = .init(), sourceColourModel: SourceColourModel? = nil) {
        self.limits = limits; self.sourceColourModel = sourceColourModel
    }
    public static var workspaceAlignment: Int { MemoryLayout<Int>.alignment }
    // Format dimensions are 16-bit; this predecessor ceiling is deliberately retained.
    internal static let maxDecodablePixels = 16 << 20
    internal struct Configuration {
        enum PixelFormat { case uint8, uint16, float32 }
        enum ColourModel { case grayscale, rgb, yCbCr }
        let maximumEncodedBytes: Int, maximumPixels: Int, maximumDecodedBytes: Int
        let maximumDimension: Int, maximumWorkspaceBytes: Int
        let sourceColorModel: ColourModel?
        let scale = 1
        let outputPixelFormat: PixelFormat? = nil
        let outputColorModel: ColourModel? = nil
    }
    private var configuration: Configuration {
        .init(maximumEncodedBytes: limits.maximumEncodedBytes, maximumPixels: limits.maximumPixels,
              maximumDecodedBytes: limits.maximumDecodedBytes,
              maximumDimension: limits.maximumDimension, maximumWorkspaceBytes: limits.maximumWorkspaceBytes,
              sourceColorModel: sourceColourModel.map { $0 == .rgb ? .rgb : .yCbCr })
    }
    private func admission(_ input: UnsafeRawBufferPointer, _ workspace: UnsafeMutableRawBufferPointer,
                           output: UnsafeMutableRawBufferPointer? = nil) -> QualifiedFailure? {
        guard limits.maximumEncodedBytes > 0, limits.maximumPixels > 0, limits.maximumDecodedBytes > 0,
              limits.maximumDimension > 0, limits.maximumWorkspaceBytes > 0, limits.maximumMemoryBytes > 0,
              limits.deadlineSeconds.isFinite, limits.deadlineSeconds > 0 else { return .init(code: 170, kind: .resourceLimit) }
        let base = input.count.addingReportingOverflow(workspace.count)
        let total = base.partialValue.addingReportingOverflow(output?.count ?? 0)
        guard !base.overflow, !total.overflow, input.count <= limits.maximumEncodedBytes,
              workspace.count <= limits.maximumWorkspaceBytes, total.partialValue <= limits.maximumMemoryBytes else {
            return .init(code: 172, kind: .resourceLimit)
        }
        return nil
    }
    private func dimensions(_ width: Int, _ height: Int, workspace: Int) -> QualifiedFailure? {
        guard width <= limits.maximumDimension, height <= limits.maximumDimension,
              workspace <= limits.maximumWorkspaceBytes else { return .init(code: 173, kind: .resourceLimit) }
        return nil
    }
    /// Inspect complete SOF3 structure; entropy validity is established only by decode.
    @available(*, noasync, message: "Run on the synchronous worker retaining all borrowed storage")
    public func inspectLosslessMonochrome(_ encoded: UnsafeRawBufferPointer,
        workspace: UnsafeMutableRawBufferPointer, cancellation: QualifiedCancellation = .never) -> QualifiedOutcome<LosslessMonochromeInfo> {
        if let failure = admission(encoded, workspace) { return .failure(failure) }
        let token: QualifiedCancellation
        switch cancellation.startingDeadline(seconds: limits.deadlineSeconds) {
        case .success(let value): token = value
        case .failure(let failure): return .failure(failure)
        }
        switch inspectLosslessMonochromeCore(encoded, workspace: workspace, configuration: configuration, cancellation: token) {
        case .failure(let failure): return .failure(failure)
        case .success(let info):
            if let failure = dimensions(info.width, info.height, workspace: Self.losslessMonochromeWorkspaceByteCount) { return .failure(failure) }
            if case .failure(let failure) = token.check() { return .failure(failure) }
            return .success(info)
        }
    }
    /// Decode packed unsigned little-endian UInt16 samples. Excess output is untouched.
    @available(*, noasync, message: "Run on the synchronous worker retaining all borrowed storage")
    public func decodeLosslessMonochrome(_ encoded: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer,
        workspace: UnsafeMutableRawBufferPointer, cancellation: QualifiedCancellation = .never) -> QualifiedOutcome<LosslessMonochromeInfo> {
        if let failure = admission(encoded, workspace, output: output) { return .failure(failure) }
        let token: QualifiedCancellation
        switch cancellation.startingDeadline(seconds: limits.deadlineSeconds) {
        case .success(let value): token = value
        case .failure(let failure): return .failure(failure)
        }
        let result = decodeLosslessMonochromeCore(encoded, into: output, workspace: workspace, configuration: configuration, cancellation: token)
        if case .failure(let failure) = token.check() { return .failure(failure) }
        return result
    }
    /// Inspect SOF0 RGB8 and return exact workspace and retained 12N-byte arena requirements.
    @available(*, noasync, message: "Run on the synchronous worker retaining all borrowed storage")
    public func inspectBaselineRGB(_ encoded: UnsafeRawBufferPointer,
        headerWorkspace: UnsafeMutableRawBufferPointer, cancellation: QualifiedCancellation = .never) -> QualifiedOutcome<BaselineRGBInfo> {
        if let failure = admission(encoded, headerWorkspace) { return .failure(failure) }
        let token: QualifiedCancellation
        switch cancellation.startingDeadline(seconds: limits.deadlineSeconds) {
        case .success(let value): token = value
        case .failure(let failure): return .failure(failure)
        }
        switch inspectBaselineRGBCore(encoded, headerWorkspace: headerWorkspace, configuration: configuration, cancellation: token) {
        case .failure(let failure): return .failure(failure)
        case .success(let info):
            if let failure = dimensions(info.width, info.height, workspace: info.workspaceByteCount) { return .failure(failure) }
            if case .failure(let failure) = token.check() { return .failure(failure) }
            return .success(info)
        }
    }
    /// Decode into the first 3N bytes of a caller-owned 12N-byte arena. Retain and
    /// account the whole arena for the result's lifetime. Scratch binding changes.
    @available(*, noasync, message: "Run on the synchronous worker retaining all borrowed storage")
    public func decodeBaselineRGB(_ encoded: UnsafeRawBufferPointer, arena: UnsafeMutableRawBufferPointer,
        workspace: UnsafeMutableRawBufferPointer, cancellation: QualifiedCancellation = .never) -> QualifiedOutcome<BaselineRGBInfo> {
        if let failure = admission(encoded, workspace, output: arena) { return .failure(failure) }
        let token: QualifiedCancellation
        switch cancellation.startingDeadline(seconds: limits.deadlineSeconds) {
        case .success(let value): token = value
        case .failure(let failure): return .failure(failure)
        }
        let result = decodeBaselineRGBCore(encoded, arena: arena, workspace: workspace, configuration: configuration, cancellation: token)
        if case .failure(let failure) = token.check() { return .failure(failure) }
        return result
    }
}
