// SPDX-License-Identifier: Apache-2.0
import Foundation

/// DCT chroma resolution. Greyscale inputs always use one full-resolution plane.
public enum ChromaSubsampling: Sendable, Equatable {
    case yuv444, yuv422, yuv420
    /// Explicit RGB-to-luma conversion when the source has colour components.
    case greyscale
}
/// XYB input is explicitly interpreted as sRGB; arbitrary source ICC conversion is not implied.
public enum DCTColourSpace: Sendable, Equatable { case yCbCr, xybFromSRGB }
public enum ColourConversion: Sendable, Equatable { case sRGBToXYB, xybToSRGB, rgbToGreyscale }
public enum DCTAlphaPolicy: Sendable, Equatable { case reject, discardStraightAlpha }
/// Preconverted YCbCr uses full-range JPEG components (8-bit Y and centred
/// Cb/Cr), or their explicitly normalised Float32 input representation.
public enum DCTSourceColourSpace: Sendable, Equatable { case fromDescriptor, yCbCr }
public enum ProgressiveMode: Sendable, Equatable { case sequential, spectralSelection, successiveApproximation }

/// Float input is rejected unless the caller explicitly permits this lossy mapping.
/// The opt-in clamps finite normalised samples to [0,1], multiplies by 255 and
/// rounds to nearest (ties away from zero). NaN and infinity always fail.
public enum FloatInputPolicy: Sendable, Equatable { case reject, normalisedClampedToUInt8 }
public enum SampleConversion: Sendable, Equatable { case normalisedFloat32ClampedToUInt8, rawSRGBToNormalisedFloat32 }

/// Explicit lossy controls; selecting these never changes the default lossless mode.
public struct DCTOptions: Sendable, Equatable {
    public let quality: Double
    public let distance: Double?
    public let chromaSubsampling: ChromaSubsampling
    public let progressiveMode: ProgressiveMode
    public let optimiseHuffman: Bool
    public let adaptiveQuantisation: Bool
    public let perceptualQuantisationTables: Bool
    /// Luma-derived trellis strength. Requires adaptiveQuantisation and 8-bit input.
    public let adaptiveQuantisationField: Bool
    /// jpegli masking/zero-bias path, replacing trellis. Requires 8-bit input.
    public let jpegliAdaptiveQuantisation: Bool
    public let floatInputPolicy: FloatInputPolicy
    public let colourSpace: DCTColourSpace
    public let alphaPolicy: DCTAlphaPolicy
    public let sourceColourSpace: DCTSourceColourSpace
    public init(quality: Double = 90, distance: Double? = nil,
                chromaSubsampling: ChromaSubsampling = .yuv420,
                progressiveMode: ProgressiveMode = .sequential,
                optimiseHuffman: Bool = true, adaptiveQuantisation: Bool = true,
                perceptualQuantisationTables: Bool = true,
                adaptiveQuantisationField: Bool = false, jpegliAdaptiveQuantisation: Bool = false,
                floatInputPolicy: FloatInputPolicy = .reject, colourSpace: DCTColourSpace = .yCbCr,
                alphaPolicy: DCTAlphaPolicy = .reject, sourceColourSpace: DCTSourceColourSpace = .fromDescriptor) {
        self.quality = quality; self.distance = distance
        self.chromaSubsampling = chromaSubsampling; self.progressiveMode = progressiveMode
        self.optimiseHuffman = optimiseHuffman; self.adaptiveQuantisation = adaptiveQuantisation
        self.perceptualQuantisationTables = perceptualQuantisationTables
        self.adaptiveQuantisationField = adaptiveQuantisationField
        self.jpegliAdaptiveQuantisation = jpegliAdaptiveQuantisation
        self.floatInputPolicy = floatInputPolicy; self.colourSpace = colourSpace
        self.alphaPolicy = alphaPolicy; self.sourceColourSpace = sourceColourSpace
    }
    var native: JLIEncoderConfiguration {
        .init(quality: quality, distance: distance,
            chromaSubsampling: chromaSubsampling == .greyscale ? .yuv400 : chromaSubsampling == .yuv444 ? .yuv444 : chromaSubsampling == .yuv422 ? .yuv422 : .yuv420,
            colorSpace: colourSpace == .xybFromSRGB ? .xyb : .yCbCr,
            progressive: progressiveMode != .sequential,
            progressiveMode: progressiveMode == .successiveApproximation ? .successiveApproximation : .spectralSelection,
            optimiseHuffman: optimiseHuffman, adaptiveQuantization: adaptiveQuantisation,
            adaptiveQuantField: adaptiveQuantisationField,
            perceptualQuantTables: perceptualQuantisationTables,
            jpegliAdaptiveQuant: jpegliAdaptiveQuantisation)
    }
}

public struct CodecOptions: Sendable, Equatable {
    public let predictor: Int
    public let restartInterval: Int
    public let dct: DCTOptions
    public init(predictor: Int = 1, restartInterval: Int = 0, dct: DCTOptions = .init()) {
        self.predictor = predictor; self.restartInterval = restartInterval; self.dct = dct
    }
}
public struct EncoderConfiguration: Sendable, Equatable {
    public let mode: CompressionMode
    public let codecOptions: CodecOptions
    public init(mode: CompressionMode = .lossless, codecOptions: CodecOptions = .init()) throws {
        guard (1...7).contains(codecOptions.predictor), (0...65535).contains(codecOptions.restartInterval) else {
            throw CodecError(.invalidArgument, "Invalid JPEG predictor or restart interval.")
        }
        if case .nearLossless(let bound) = mode, bound <= 0 {
            throw CodecError(.invalidArgument, "Near-lossless error must be positive.")
        }
        let dct = codecOptions.dct
        guard dct.quality.isFinite, (0...100).contains(dct.quality),
              dct.distance.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw CodecError(.invalidArgument, "DCT quality must be 0...100 and distance nonnegative, both finite.")
        }
        guard !dct.adaptiveQuantisationField || (dct.adaptiveQuantisation && !dct.jpegliAdaptiveQuantisation) else {
            throw CodecError(.invalidArgument, "Adaptive trellis fields require trellis and cannot be combined with jpegli zero-bias quantisation.")
        }
        if dct.colourSpace == .xybFromSRGB {
            guard dct.chromaSubsampling == .yuv444, dct.progressiveMode == .sequential,
                  codecOptions.restartInterval == 0, dct.perceptualQuantisationTables,
                  !dct.jpegliAdaptiveQuantisation else {
                throw CodecError(.unsupportedFeature, "XYB requires sequential 4:4:4, perceptual tables, no restarts and no jpegli zero-bias field.")
            }
        }
        guard dct.sourceColourSpace != .yCbCr || (dct.colourSpace == .yCbCr && dct.chromaSubsampling != .greyscale && dct.alphaPolicy == .reject) else {
            throw CodecError(.unsupportedFeature, "Preconverted YCbCr cannot request RGB/alpha-specific conversions.")
        }
        guard mode == .lossy || dct == DCTOptions() else {
            throw CodecError(.invalidArgument, "DCT options require explicit lossy mode.")
        }
        guard mode != .lossy || codecOptions.predictor == 1 else {
            throw CodecError(.invalidArgument, "Predictor selection applies only to predictive JPEG.")
        }
        self.mode = mode; self.codecOptions = codecOptions
    }
    /// JPEG point transforms have error bounds 2^Pt - 1. Select the
    /// greatest representable bound no larger than the caller's maximum.
    /// Pt must remain below sample precision, including for a generous budget.
    func pointTransform(precision: Int) -> Int {
        guard case .nearLossless(let bound) = mode else { return 0 }
        let candidate = bound == Int.max ? 15 : Int.bitWidth - (bound + 1).leadingZeroBitCount - 1
        return min(15, min(precision - 1, candidate))
    }
    private init() { mode = .lossless; codecOptions = .init() }
    public static let `default` = Self()
}
/// Float output has an explicit range policy. Raw samples are greyscale DCT
/// without ICC; normalised sRGB is the fractional XYB inverse divided by 255.
public enum DecoderSampleFormat: Sendable, Equatable {
    case nativeInteger, float32RawSamples, float32NormalisedSRGB
}

public struct DecoderConfiguration: Sendable, Equatable {
    public let codecOptions: CodecOptions
    /// DCT output dimensions are ceil(encoded dimension / scale).
    /// Predictive JPEG requires scale 1. Inspect always describes the codestream.
    public let scale: Int
    public let sampleFormat: DecoderSampleFormat
    public init(codecOptions: CodecOptions = .init(), scale: Int = 1,
                sampleFormat: DecoderSampleFormat = .nativeInteger) {
        self.codecOptions = codecOptions; self.scale = scale; self.sampleFormat = sampleFormat
    }
}

public struct CodecCapabilities: Sendable, Equatable {
    public let formats: [String]
    public let compressionModes: [CompressionMode]
    public let sampleTypes: [SampleType]
    public let meaningfulPrecision: ClosedRange<Int>?
    public let layouts: [String]
    public let availableBackends: [Backend]
    public let canInspect: Bool
    public let canEncode: Bool
    public let canDecode: Bool
    public static let contractOnly = Self(formats: [], compressionModes: [], sampleTypes: [],
        meaningfulPrecision: nil, layouts: [], availableBackends: [],
        canInspect: false, canEncode: false, canDecode: false)
}

public struct CopyEvent: Sendable, Equatable {
    public let reason: String
    public let bytesMoved: Int
    public let sourceLayout: String
    public let destinationLayout: String
    public init(reason: String, bytesMoved: Int, sourceLayout: String, destinationLayout: String) throws {
        guard bytesMoved >= 0 else { throw CodecError(.invalidArgument, "Copy byte count must not be negative.") }
        self.reason = reason; self.bytesMoved = bytesMoved
        self.sourceLayout = sourceLayout; self.destinationLayout = destinationLayout
    }
}
public enum Fidelity: Sendable, Equatable { case exactSamples, boundedError(Int), lossy, originalBitstream }
public struct OperationReport: Sendable, Equatable {
    public let backend: Backend
    public let fallbackReason: String?
    public let fidelity: Fidelity
    public let copyEvents: [CopyEvent]
    public let pixelAllocationCount: Int?
    public let peakPixelBytes: Int?
    public let peakWorkspaceBytes: Int?
    public let elapsedSeconds: Double?
    /// Explicit sample-value conversion, separate from memory-copy accounting.
    public let sampleConversion: SampleConversion?
    public let colourConversion: ColourConversion?
    public let alphaDiscarded: Bool
    public init(backend: Backend, fallbackReason: String? = nil, fidelity: Fidelity,
                copyEvents: [CopyEvent] = [], pixelAllocationCount: Int? = nil,
                peakPixelBytes: Int? = nil, peakWorkspaceBytes: Int? = nil, elapsedSeconds: Double? = nil,
                sampleConversion: SampleConversion? = nil, colourConversion: ColourConversion? = nil,
                alphaDiscarded: Bool = false) {
        self.backend = backend; self.fallbackReason = fallbackReason; self.fidelity = fidelity
        self.copyEvents = copyEvents; self.pixelAllocationCount = pixelAllocationCount
        self.peakPixelBytes = peakPixelBytes; self.peakWorkspaceBytes = peakWorkspaceBytes
        self.elapsedSeconds = elapsedSeconds; self.sampleConversion = sampleConversion
        self.colourConversion = colourConversion
        self.alphaDiscarded = alphaDiscarded
    }
}
public struct ImageInfo: Sendable {
    public let format: String
    public let descriptor: ImageDescriptor
    public let frameCount: Int
    public let metadata: ImageMetadata
}
public struct EncodingDescription: Sendable, Equatable {
    public let format: String
    public let mode: CompressionMode
}
public struct EncodedImage: Sendable {
    public let data: Data
    public let encoding: EncodingDescription
    public let report: OperationReport
}
public struct DecodedImage: Sendable {
    public let image: Image
    public let report: OperationReport
}

/// Reusable configuration; operation state is isolated in each invocation.
public struct Encoder: Sendable {
    public let configuration: EncoderConfiguration
    public static let capabilities = JPEGCodec.capabilities
    public var capabilities: CodecCapabilities { Self.capabilities }
    public init(configuration: EncoderConfiguration = .default) throws { self.configuration = configuration }

    @concurrent public func encode(_ image: Image, options: EncodeOptions = .init()) async throws -> EncodedImage {
        try await NativeOperation.withCancellation {
            try JPEGCodec.encode(image, configuration: configuration, options: options)
        }
    }
}

public struct Decoder: Sendable {
    public let configuration: DecoderConfiguration
    public static let capabilities = JPEGCodec.decoderCapabilities
    public var capabilities: CodecCapabilities { Self.capabilities }
    public init(configuration: DecoderConfiguration = .init()) throws {
        guard configuration.codecOptions == CodecOptions() else {
            throw CodecError(.unsupportedFeature, "Predictor and restart controls are encoder options; decode reads them from JPEG.")
        }
        guard [1, 2, 4, 8].contains(configuration.scale) else {
            throw CodecError(.invalidArgument, "JPEG decode scale must be 1, 2, 4 or 8.")
        }
        self.configuration = configuration
    }

    public func inspect(_ data: Data, options: DecodeOptions = .init()) throws -> ImageInfo {
        try JPEGCodec.inspect(data, options: options)
    }
    @concurrent public func decode(_ data: Data, options: DecodeOptions = .init()) async throws -> DecodedImage {
        try await NativeOperation.withCancellation {
            try JPEGCodec.decode(data, into: nil, configuration: configuration, options: options)
        }
    }
    @concurrent public func decode(_ data: Data, into destination: ImageDestination,
                                  options: DecodeOptions = .init()) async throws -> DecodedImage {
        try await NativeOperation.withCancellation {
            try JPEGCodec.decode(data, into: destination, configuration: configuration, options: options)
        }
    }
}
