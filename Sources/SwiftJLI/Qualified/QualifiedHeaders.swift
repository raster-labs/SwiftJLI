// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
struct QualifiedComponentInfo {
    let id: UInt8
    let horizontalSampling: Int
    let verticalSampling: Int
    let quantTableIndex: Int
}
struct QualifiedFrameInfo {
    let precision: Int
    let width: Int
    let height: Int
    let components: QualifiedStorageArray<QualifiedComponentInfo>
    let isProgressive: Bool
    /// SOF3 — lossless (predictive, no DCT). The SOS `spectralStart` carries the
    /// predictor selection (1–7) and `successiveApproxLow` the point transform.
    var isLossless: Bool = false
}
struct QualifiedScanHeader {
    let components: QualifiedStorageArray<QualifiedScanComponent>
    let spectralStart: Int
    let spectralEnd: Int
    let successiveApproxHigh: Int
    let successiveApproxLow: Int
}
struct QualifiedScanData { let header: QualifiedScanHeader }
struct QualifiedParsedJPEG { let frameInfo: QualifiedFrameInfo; let scans: QualifiedStorageArray<QualifiedScanData> }
enum QualifiedFrameSlot {
    case none
    case some(QualifiedFrameInfo)
}
enum QualifiedParseOutcome {
    case success(QualifiedParsedJPEG)
    case failure(QualifiedFailure)
    var failureValue: QualifiedFailure {
        switch self {
        case .failure(let failure): return failure
        case .success: preconditionFailure("Expected an already-checked failure")
        }
    }
}
enum QualifiedFrameOutcome {
    case success(QualifiedFrameInfo)
    case failure(QualifiedFailure)
    var failureValue: QualifiedFailure {
        switch self {
        case .failure(let failure): return failure
        case .success: preconditionFailure("Expected an already-checked failure")
        }
    }
}
enum QualifiedScanHeaderOutcome {
    case success(QualifiedScanHeader)
    case failure(QualifiedFailure)
    var failureValue: QualifiedFailure {
        switch self {
        case .failure(let failure): return failure
        case .success: preconditionFailure("Expected an already-checked failure")
        }
    }
}
