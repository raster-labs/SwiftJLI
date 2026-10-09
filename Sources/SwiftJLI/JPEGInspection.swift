// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The JPEG coding process. Predictive JPEG may use a nonzero point transform;
/// its process name alone does not establish exact reconstruction.
public enum JPEGCodingProcess: Sendable, Equatable {
    case predictive, sequentialDCT, progressiveDCT
}

/// Relative component sampling. These conventional labels describe geometry,
/// not a promise that the encoded components have YCbCr colour meaning.
public enum JPEGChromaSubsampling: Sendable, Equatable {
    case greyscale, yuv444, yuv422, yuv420, other
}

public struct JPEGComponentSampling: Sendable, Equatable {
    public let identifier: UInt8
    public let horizontalFactor: Int
    public let verticalFactor: Int
}

/// Bounded JPEG-specific inspection, including information that cannot be
/// represented by the common full-resolution ImageInfo descriptor. Inspection
/// validates supported structure; it does not certify entropy or sample fidelity.
public struct JPEGInspection: Sendable {
    public let imageInfo: ImageInfo
    public let codingProcess: JPEGCodingProcess
    public let componentSampling: [JPEGComponentSampling]
    public let chromaSubsampling: JPEGChromaSubsampling
    /// True only for the recognised XYB profile and validated JPEG interpretation.
    public let isXYB: Bool
    public let restartInterval: Int
    public let scanCount: Int
    /// Present only for predictive JPEG; one validated scan is supported.
    public let predictor: Int?
    public let pointTransform: Int?

    public var width: Int { imageInfo.descriptor.width }
    public var height: Int { imageInfo.descriptor.height }
    public var componentCount: Int { componentSampling.count }
    public var bitsPerComponent: Int { imageInfo.descriptor.meaningfulBits }
    public var isProgressive: Bool { codingProcess == .progressiveDCT }
    public var isExtendedPrecision: Bool { bitsPerComponent > 8 }
}

extension Decoder {
    /// Returns encoded geometry, precision, sampling and coding features through
    /// the same bounded parser as inspect(_:options:), without decoding pixels.
    /// Decode scale/sample-format configuration does not reinterpret inspection.
    public func inspectJPEG(_ data: Data, options: DecodeOptions = .init()) throws -> JPEGInspection {
        try JPEGCodec.inspectJPEG(data, options: options)
    }
}

extension JPEGCodec {
    static func inspectJPEG(_ data: Data, options: DecodeOptions) throws -> JPEGInspection {
        try run(limits: options.resourceLimits, policy: .scalarCPU) {
            let parsed = try parse(data, options: options)
            let frame = parsed.frameInfo
            _ = try selectBackend(options.executionPolicy, dct: !frame.isLossless)
            let information = try info(parsed, options: options)
            let components = frame.components.map {
                JPEGComponentSampling(identifier: $0.id, horizontalFactor: $0.horizontalSampling,
                    verticalFactor: $0.verticalSampling)
            }
            let sampling: JPEGChromaSubsampling
            if components.count == 1 { sampling = .greyscale }
            else if components.count == 3 {
                let a = components[0], b = components[1], c = components[2]
                if b.horizontalFactor != c.horizontalFactor || b.verticalFactor != c.verticalFactor { sampling = .other }
                else if a.horizontalFactor == b.horizontalFactor && a.verticalFactor == b.verticalFactor { sampling = .yuv444 }
                else if a.horizontalFactor == 2 * b.horizontalFactor && a.verticalFactor == b.verticalFactor { sampling = .yuv422 }
                else if a.horizontalFactor == 2 * b.horizontalFactor && a.verticalFactor == 2 * b.verticalFactor { sampling = .yuv420 }
                else { sampling = .other }
            } else { sampling = .other }
            let scan = parsed.scans.first
            try NativeOperation.check()
            return JPEGInspection(imageInfo: information,
                codingProcess: frame.isLossless ? .predictive : frame.isProgressive ? .progressiveDCT : .sequentialDCT,
                componentSampling: components, chromaSubsampling: sampling,
                isXYB: parsed.iccProfile == XYBICCProfile.data,
                restartInterval: parsed.restartInterval, scanCount: parsed.scans.count,
                predictor: frame.isLossless ? scan?.header.spectralStart : nil,
                pointTransform: frame.isLossless ? scan?.header.successiveApproxLow : nil)
        }
    }
}
