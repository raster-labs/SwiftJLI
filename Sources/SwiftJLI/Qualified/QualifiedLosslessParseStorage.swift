// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
enum QualifiedParseCapture {
    case lossless(QualifiedLosslessParseStorage), baseline(QualifiedBaselineParseStorage)
    var maximumScans: Int { switch self { case .lossless: 1; case .baseline: 3 } }
    var records: QualifiedCallerRecords { switch self { case .lossless(let s): s.records; case .baseline(let s): s.records } }
    func accepts(componentCount: Int) -> Bool { switch self { case .lossless: componentCount == 1; case .baseline: (1...3).contains(componentCount) } }
    func table(isDC: Bool, id: Int, bits: Int, values: Int, count: Int) {
        switch self { case .lossless(let s): s.table(isDC: isDC, id: id, bits: bits, values: values, count: count)
        case .baseline(let s): s.table(isDC: isDC, id: id, bits: bits, values: values, count: count) }
    }
    func quantization(id: Int, precision: Int, range: Range<Int>) {
        if case .baseline(let s) = self { s.quantization(id: id, precision: precision, range: range) }
    }
    func application(marker: UInt8, range: Range<Int>, input: QualifiedByteView) {
        if case .baseline(let s) = self { s.application(marker: marker, range: range, input: input) }
    }
    func scan(_ scan: QualifiedScanHeader, frame: QualifiedFrameSlot, entropy: Range<Int>, restartInterval: Int) -> QualifiedOutcome<Void> {
        switch self {
        case .lossless(let storage): return storage.scan(scan, frame: frame, entropy: entropy, restartInterval: restartInterval)
        case .baseline(let storage): return storage.scan(scan, frame: frame, entropy: entropy, restartInterval: restartInterval)
        }
    }
}

struct QualifiedLosslessParseStorage {
    static let headerByteCount = 5120
    let records: QualifiedCallerRecords
    private let state: UnsafeMutablePointer<State>
    private struct State {
        var selected = Descriptor()
        var selectedID = 0
        var entropy = 0..<0
        var restartInterval = 0
    }
    let maximumScans = 1
    func accepts(componentCount: Int) -> Bool { componentCount == 1 }
    func quantization(id: Int, precision: Int, range: Range<Int>) {}
    func application(marker: UInt8, range: Range<Int>, input: QualifiedByteView) {}
    struct Descriptor {
        var bits = 0
        var values = 0
        var count = -1
    }
    let descriptors: UnsafeMutableBufferPointer<Descriptor>
    var selected: Descriptor { state.pointee.selected }
    var selectedID: Int { state.pointee.selectedID }
    var entropy: Range<Int> { state.pointee.entropy }
    var restartInterval: Int { state.pointee.restartInterval }
    init(workspace: UnsafeMutableRawBufferPointer) {
        precondition(workspace.count >= Self.headerByteCount)
        descriptors = UnsafeMutableRawBufferPointer(rebasing: workspace[..<(16 * MemoryLayout<Descriptor>.stride)]).bindMemory(to: Descriptor.self)
        descriptors.initialize(repeating: Descriptor())
        state = (workspace.baseAddress! + 512).bindMemory(to: State.self, capacity: 1)
        precondition(512 + MemoryLayout<State>.stride <= 1024)
        state.initialize(to: State())
        records = QualifiedCallerRecords(UnsafeMutableRawBufferPointer(rebasing: workspace[1024..<Self.headerByteCount]))
    }
    func table(isDC: Bool, id: Int, bits: Int, values: Int, count: Int) {
        guard isDC else { return }
        descriptors[id] = Descriptor(bits: bits, values: values, count: count)
    }
    func scan(_ scan: QualifiedScanHeader, frame: QualifiedFrameSlot, entropy: Range<Int>, restartInterval: Int) -> QualifiedOutcome<Void> {
        guard case .some(let frame) = frame, frame.isLossless, frame.components.count == 1 else {
            return .failure(QualifiedFailure(code: 133, kind: .unsupported))
        }
        guard scan.components.count == 1, scan.components[0].componentSelector == frame.components[0].id,
              scan.spectralEnd == 0, scan.successiveApproxHigh == 0 else {
            return .failure(QualifiedFailure(code: 176, kind: .decoding))
        }
        state.pointee.selectedID = scan.components[0].dcTableId
        state.pointee.selected = descriptors[selectedID]
        state.pointee.entropy = entropy
        state.pointee.restartInterval = restartInterval
        return .success(())
    }
}

protocol QualifiedLosslessSampleStorage {
    subscript(index: Int) -> Int32 { get nonmutating set }
}
/// The canonical kernel still computes Int32 predictions/modulo-65536 samples;
/// only their storage changes. Final point-transform serialization is in place.
struct QualifiedLosslessLittleEndianSamples: QualifiedLosslessSampleStorage {
    let bytes: UnsafeMutableRawBufferPointer
    subscript(index: Int) -> Int32 {
        get { Int32(bytes[index * 2]) | Int32(bytes[index * 2 + 1]) << 8 }
        nonmutating set {
            bytes[index * 2] = UInt8(truncatingIfNeeded: newValue)
            bytes[index * 2 + 1] = UInt8(truncatingIfNeeded: newValue >> 8)
        }
    }
}

/// Concrete ownership carrier for the shared lossless validation result.
enum QualifiedLosslessParametersOutcome {
    case success((predictor: Int, pointTransform: Int, scan: QualifiedScanData))
    case failure(QualifiedFailure)
    var failureValue: QualifiedFailure {
        switch self {
        case .failure(let failure): return failure
        case .success: preconditionFailure("Expected an already-checked failure")
        }
    }
}

