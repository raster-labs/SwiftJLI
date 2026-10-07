// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Synchronous kernels borrow the operation's cancellation/deadline context.
/// The shared path stays on its invoking task; legacy Dispatch workers are not
/// used here, so the task-local context and cancellation cannot be lost.
struct NativeOperation: Sendable {
    @TaskLocal static var current: NativeOperation?
    let started: ContinuousClock.Instant
    let seconds: Double
    let backend: Backend
    init(seconds: Double, backend: Backend = .scalarCPU, started: ContinuousClock.Instant = .now) {
        self.seconds = seconds; self.backend = backend; self.started = started
    }
    static func check() throws {
        try Task.checkCancellation()
        if let context = current, context.started.duration(to: .now) >= .seconds(context.seconds) {
            throw CodecError(.resourceLimitExceeded, "JPEG operation deadline exceeded.")
        }
    }
}

/// Common owning-storage adapter for predictive and DCT JPEG kernels.
enum JPEGCodec {
    static let capabilities = CodecCapabilities(
        formats: ["JPEG (SOF0/SOF1/SOF2/SOF3)"], compressionModes: [.lossless, .lossy] +
            (1...15).map { .nearLossless(maximumAbsoluteError: (1 << $0) - 1) },
        sampleTypes: [.unsignedInteger, .floatingPoint], meaningfulPrecision: nil,
        layouts: ["greyscale8", "greyscale16", "rgb8", "rgb16", "normalisedGreyscaleFloat32", "normalisedRGBFloat32"],
        availableBackends: availableBackends, canInspect: false, canEncode: true, canDecode: false)

    // Decoder profiles include integer 2...16 and IEEE Float32, not a single
    // continuous precision range. Encoding floats requires an explicit lossy policy.
    static let decoderCapabilities = CodecCapabilities(formats: capabilities.formats,
        compressionModes: capabilities.compressionModes, sampleTypes: [.unsignedInteger, .floatingPoint],
        meaningfulPrecision: nil, layouts: ["greyscale8", "greyscale16", "rgb8", "rgb16", "greyscaleFloat32RawSamples", "rgbFloat32NormalisedSRGB"],
        availableBackends: capabilities.availableBackends, canInspect: true, canEncode: false, canDecode: true)

    static var availableBackends: [Backend] {
        #if canImport(Accelerate)
        [.scalarCPU, .accelerated]
        #else
        [.scalarCPU]
        #endif
    }

    static func selectBackend(_ policy: ExecutionPolicy, dct: Bool) throws -> Backend {
        let accelerated = dct && availableBackends.contains(.accelerated)
        switch policy {
        case .scalarCPU, .preferred(.scalarCPU), .required(.scalarCPU): return .scalarCPU
        case .required(.accelerated):
            guard accelerated else { throw CodecError(.backendUnavailable, "Requested JPEG backend is unavailable for this operation.") }
            return .accelerated
        case .automatic, .preferred(.accelerated): return accelerated ? .accelerated : .scalarCPU
        }
    }

    static func run<T>(limits: ResourceLimits, policy: ExecutionPolicy, dct: Bool = false,
                       _ body: () throws -> T) throws -> T {
        let backend = try selectBackend(policy, dct: dct)
        return try NativeOperation.$current.withValue(NativeOperation(seconds: limits.deadlineSeconds, backend: backend)) {
            try NativeOperation.check()
            do { return try body() }
            catch let error as JLIError {
                switch error {
                case .invalidJPEGData, .decodingFailed:
                    throw CodecError(.malformedInput, "Invalid JPEG structure or entropy data.")
                case .unsupportedJPEGFeature, .unsupportedColorSpaceConversion, .notImplemented:
                    throw CodecError(.unsupportedFeature, "Unsupported JPEG feature.")
                case .encodingFailed:
                    throw CodecError(.internalFailure, "JPEG encoding failed.")
                default:
                    throw CodecError(.invalidArgument, "Invalid JPEG configuration or samples.")
                }
            }
        }
    }

    static func fallback(_ policy: ExecutionPolicy) -> String? {
        if case .preferred(.accelerated) = policy, NativeOperation.current?.backend == .scalarCPU { return "The accelerated backend is unavailable for this JPEG operation." }
        return nil
    }

    static func layout(_ descriptor: ImageDescriptor, allowFloat: Bool = false, limits: ResourceLimits) throws -> PlaneDescriptor {
        try descriptor.validate(limits: limits)
        let grey = descriptor.components == [.grey] && descriptor.colour == .greyscale
        let rgb = descriptor.components == [.red, .green, .blue] && descriptor.colour == .rgb
        let integer = descriptor.sampleType == .unsignedInteger && (2...16).contains(descriptor.meaningfulBits)
            && (descriptor.storageBits == 8 || descriptor.storageBits == 16)
        let floating = allowFloat && descriptor.sampleType == .floatingPoint
            && descriptor.meaningfulBits == 32 && descriptor.storageBits == 32
        guard integer || floating, descriptor.alpha == .absent, grey || rgb else {
            throw CodecError(.unsupportedFeature, "Unsupported JPEG sample type, precision, components or alpha.")
        }
        guard descriptor.width <= 65535, descriptor.height <= 65535 else {
            throw CodecError(.unsupportedFeature, "JPEG dimensions exceed the 16-bit frame fields.")
        }
        let bps = descriptor.storageBits / 8
        guard descriptor.planes.count == 1, descriptor.byteOrder == .littleEndian || bps == 1,
              let plane = descriptor.planes.first,
              plane.components == Array(descriptor.components.indices),
              plane.sampleStride == bps, plane.pixelStride == bps * descriptor.components.count else {
            throw CodecError(.incompatibleImageLayout, "JPEG currently requires interleaved little-endian storage.")
        }
        return plane
    }

    /// Conservative admission reservation, not a measured peak. Includes array
    /// growth, tables, compressed copies and the native Int32 working planes.
    static func admit(workspace: Int, pixels: Int, compressed: Int, metadata: Int,
                      limits: ResourceLimits) throws {
        guard workspace <= limits.maximumWorkspaceBytes,
              pixels <= limits.maximumDecodedBytes, compressed <= limits.maximumCompressedBytes,
              try checkedAdd(checkedAdd(workspace, pixels), checkedAdd(compressed, metadata)) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "JPEG operation exceeds its memory budget.")
        }
    }

    static func encode(_ image: Image, configuration: EncoderConfiguration, options: EncodeOptions) throws -> EncodedImage {
        try run(limits: options.resourceLimits, policy: options.executionPolicy, dct: configuration.mode == .lossy) {
            let limits = options.resourceLimits, d = image.descriptor
            let isDCT = configuration.mode == .lossy
            let floating = d.sampleType == .floatingPoint
            let allowsFloat = isDCT && configuration.codecOptions.dct.floatInputPolicy == .normalisedClampedToUInt8
            guard !allowsFloat || floating else {
                throw CodecError(.invalidArgument, "Float input policy requires Float32 source samples.")
            }
            let plane = try layout(d, allowFloat: allowsFloat, limits: limits)
            let precision = floating ? 8 : d.meaningfulBits
            let xyb = configuration.codecOptions.dct.colourSpace == .xybFromSRGB
            if xyb {
                guard precision == 8, d.components == [.red, .green, .blue],
                      d.iccProfile == nil || d.iccProfile == Data(SRGBICCProfile.data) else {
                    throw CodecError(.unsupportedFeature, "XYB input requires 8-bit sRGB or explicitly quantised normalised sRGB; an unknown ICC profile cannot be reinterpreted.")
                }
            }
            guard !isDCT || floating || (d.meaningfulBits == 8 && d.storageBits == 8) || (d.meaningfulBits == 12 && d.storageBits == 16) else {
                throw CodecError(.unsupportedFeature, "DCT encoding requires 8-bit samples or 12-bit samples in 16-bit storage.")
            }
            if isDCT && (configuration.codecOptions.dct.adaptiveQuantisationField || configuration.codecOptions.dct.jpegliAdaptiveQuantisation), precision != 8 {
                throw CodecError(.unsupportedFeature, "Adaptive DCT fields require 8-bit input.")
            }
            let metadataBytes = try image.metadata.validate(limits: limits, additionalBytes: xyb ? XYBICCProfile.data.count : d.iccProfile?.count ?? 0)
            // ICC defines interpretation and is retained even when ancillary data is discarded.
            let keys = options.metadataPolicy == .preserve ? Set(image.metadata.entries.keys) : image.metadata.requiredKeys
            guard keys.isSubset(of: ["Exif"]) else {
                throw CodecError(.unsupportedFeature, "JPEG cannot preserve the requested metadata keys.")
            }
            let exif = keys.contains("Exif") ? image.metadata.entries["Exif"] : nil
            guard !isDCT || d.iccProfile?.elementsEqual(XYBICCProfile.data) != true else {
                throw CodecError(.unsupportedFeature, "XYB colour interpretation is not exposed by the common DCT adapter.")
            }
            guard (exif?.count ?? 0) <= 65527, (d.iccProfile?.count ?? 0) <= 255 * 65519 else {
                throw CodecError(.unsupportedFeature, "Metadata exceeds JPEG segment capacity.")
            }
            let samples = try checkedMultiply(checkedMultiply(d.width, d.height), d.components.count)
            let outputBound = try checkedAdd(checkedMultiply(samples, 8), checkedAdd(checkedMultiply(metadataBytes, 2), 4096))
            let workspace = try checkedAdd(checkedMultiply(samples, isDCT ? 192 : 64), checkedAdd(checkedMultiply(metadataBytes, 4), 1_048_576))
            try admit(workspace: workspace, pixels: image.storage.byteCount, compressed: outputBound,
                      metadata: metadataBytes, limits: limits)
            var cfg = isDCT ? configuration.codecOptions.dct.native : JLIEncoderConfiguration.diagnosticLossless
            cfg.losslessPrecision = precision
            cfg.losslessPointTransform = configuration.pointTransform(precision: precision)
            cfg.losslessPredictor = configuration.codecOptions.predictor
            cfg.restartInterval = configuration.codecOptions.restartInterval
            guard isDCT || cfg.restartInterval == 0 || cfg.restartInterval % d.width == 0 else {
                throw CodecError(.invalidArgument, "Lossless restart interval must contain complete rows.")
            }
            try options.progress?(.init(phase: .processing, completedUnits: 0, totalUnits: d.height))
            let encoded: [UInt8] = try image.storage.withUnsafeBytes { raw in
                guard raw.count == image.storage.byteCount, raw.count >= d.requiredByteCount else {
                    throw CodecError(.storageUnavailable, "Source provider returned inconsistent capacity.")
                }
                let bps = d.storageBits / 8, maxSample = UInt32(1) << precision
                // Float finiteness is checked by the fused quantising reader.
                if !floating {
                    for y in 0..<d.height {
                        try NativeOperation.check()
                        for x in 0..<(d.width * d.components.count) {
                            let offset = plane.offset + y * plane.rowBytes + x * bps
                            let value = UInt32(raw[offset]) | (bps == 2 ? UInt32(raw[offset + 1]) << 8 : 0)
                            guard value < maxSample else {
                                throw CodecError(.invalidArgument, "Sample exceeds declared meaningful precision.")
                            }
                        }
                    }
                }
                if isDCT {
                    return try JLIEncoder().encodeSharedDCT(
                        from: .init(bytes: .init(rebasing: raw[plane.offset...]), rowBytes: plane.rowBytes),
                        width: d.width, height: d.height, precision: precision, components: d.components.count,
                        normalisedFloatInput: floating,
                        icc: d.iccProfile.map { Array($0) }, exif: exif.map { Array($0) }, configuration: cfg)
                }
                return try JLIEncoder().encodeSharedLossless(
                    from: BorrowedSamplePlane(bytes: .init(rebasing: raw[plane.offset...]), rowBytes: plane.rowBytes),
                    width: d.width, height: d.height, precision: d.meaningfulBits,
                    storageBits: d.storageBits, components: d.components.count,
                    icc: d.iccProfile.map { Array($0) }, exif: exif.map { Array($0) }, configuration: cfg)
            }
            guard encoded.count <= limits.maximumCompressedBytes else {
                throw CodecError(.resourceLimitExceeded, "Encoded JPEG exceeds compressed byte limit.")
            }
            try NativeOperation.check()
            try options.progress?(.init(phase: .completed, completedUnits: d.height, totalUnits: d.height))
            try NativeOperation.check()
            let errorBound = (1 << cfg.losslessPointTransform) - 1
            let mode: CompressionMode = isDCT ? .lossy : errorBound == 0 ? .lossless : .nearLossless(maximumAbsoluteError: errorBound)
            return EncodedImage(data: Data(encoded), encoding: .init(format: "JPEG", mode: mode),
                report: .init(backend: NativeOperation.current?.backend ?? .scalarCPU, fallbackReason: fallback(options.executionPolicy),
                              fidelity: isDCT ? .lossy : errorBound == 0 ? .exactSamples : .boundedError(errorBound),
                              pixelAllocationCount: 0, peakPixelBytes: 0,
                              sampleConversion: floating ? .normalisedFloat32ClampedToUInt8 : nil,
                              colourConversion: xyb ? .sRGBToXYB : nil))
        }
    }

    static func parse(_ data: Data, options: DecodeOptions) throws -> ParsedJPEG {
        let limits = options.resourceLimits
        // Bound copies/table storage before materialising the array or parsing.
        let parserBudget = try checkedAdd(checkedMultiply(data.count, 64), 1_048_576)
        try admit(workspace: parserBudget, pixels: 0, compressed: data.count, metadata: 0, limits: limits)
        let bytes = Array(data)
        let adobeTransform = try JPEGEnvelope.validate(bytes, limits: limits)
        var reader = MarkerReader(data: bytes)
        let parsed = try reader.parse()
        let f = parsed.frameInfo
        if !f.isLossless {
            let xyb = parsed.iccProfile == XYBICCProfile.data
            guard xyb ? adobeTransform == 0 : adobeTransform != 0 else {
                throw CodecError(.unsupportedFeature, "Direct-component JPEG requires the recognised XYB profile and Adobe transform 0.")
            }
            try validateDCT(parsed); return parsed
        }
        guard parsed.scans.count == 1, let scan = parsed.scans.first,
              scan.header.components.map(\.componentSelector) == f.components.map(\.id),
              f.components.allSatisfy({ $0.horizontalSampling == 1 && $0.verticalSampling == 1 }),
              scan.header.successiveApproxHigh == 0, scan.header.spectralEnd == 0,
              (1...7).contains(scan.header.spectralStart),
              scan.header.successiveApproxLow < f.precision else {
            throw CodecError(.unsupportedFeature, "Unsupported lossless scan layout.")
        }
        for component in scan.header.components {
            guard let table = scan.dcTables[component.dcTableId], table.values.allSatisfy({ $0 <= 16 }) else {
                throw CodecError(.malformedInput, "Lossless scan has invalid or absent Huffman tables.")
            }
        }
        return parsed
    }

    static func info(_ parsed: ParsedJPEG, scale: Int = 1, sampleFormat: DecoderSampleFormat = .nativeInteger, decodedOutput: Bool = false, options: DecodeOptions) throws -> ImageInfo {
        let f = parsed.frameInfo, nc = f.components.count
        guard (2...16).contains(f.precision), nc == 1 || nc == 3 else {
            throw CodecError(.unsupportedFeature, "Unsupported JPEG precision or component count.")
        }
        // SOF3 has no colour conversion. Accept only explicit RGB identifiers for colour.
        guard !f.isLossless || nc == 1 || f.components.map(\.id) == [0x52, 0x47, 0x42] else {
            throw CodecError(.unsupportedFeature, "Lossless colour interpretation is ambiguous.")
        }
        guard !f.isLossless || scale == 1 else {
            throw CodecError(.unsupportedFeature, "Reduced-scale decode requires DCT JPEG.")
        }
        let xyb = parsed.iccProfile == XYBICCProfile.data
        let floating = sampleFormat != .nativeInteger
        guard sampleFormat != .float32NormalisedSRGB || (xyb && !f.isLossless) else {
            throw CodecError(.unsupportedFeature, "Normalised Float32 sRGB output requires recognised XYB JPEG.")
        }
        guard sampleFormat != .float32RawSamples || (!f.isLossless && nc == 1 && parsed.iccProfile == nil) else {
            throw CodecError(.unsupportedFeature, "Raw Float32 output requires greyscale DCT JPEG without ICC interpretation.")
        }
        let width = (f.width + scale - 1) / scale, height = (f.height + scale - 1) / scale
        let bps = floating ? 4 : f.precision <= 8 ? 1 : 2
        let row = try checkedMultiply(width, nc * bps)
        let capacity = try checkedMultiply(row, height)
        let plane = try PlaneDescriptor(width: width, height: height, components: Array(0..<nc),
            sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: capacity)
        let descriptor = try ImageDescriptor(width: width, height: height,
            sampleType: floating ? .floatingPoint : .unsignedInteger, storageBits: bps * 8,
            meaningfulBits: floating ? 32 : f.precision,
            components: xyb && !decodedOutput ? [.uninterpreted("X"), .uninterpreted("Y"), .uninterpreted("B")] : nc == 1 ? [.grey] : [.red, .green, .blue],
            colour: xyb && !decodedOutput ? .unknown : nc == 1 ? .greyscale : .rgb, planes: [plane],
            iccProfile: xyb && decodedOutput ? Data(SRGBICCProfile.data) : parsed.iccProfile.map { Data($0) }, limits: options.resourceLimits)
        let metadata = ImageMetadata(entries: options.metadataPolicy == .preserve
            ? parsed.exif.map { ["Exif": Data($0)] } ?? [:] : [:])
        try metadata.validate(limits: options.resourceLimits, additionalBytes: descriptor.iccProfile?.count ?? 0)
        return ImageInfo(format: "JPEG", descriptor: descriptor, frameCount: 1, metadata: metadata)
    }

    static func inspect(_ data: Data, options: DecodeOptions) throws -> ImageInfo {
        try run(limits: options.resourceLimits, policy: .scalarCPU) {
            let parsed = try parse(data, options: options)
            _ = try selectBackend(options.executionPolicy, dct: !parsed.frameInfo.isLossless)
            let result = try info(parsed, options: options)
            try NativeOperation.check()
            return result
        }
    }

    static func decode(_ data: Data, into supplied: ImageDestination?, configuration: DecoderConfiguration, options: DecodeOptions) throws -> DecodedImage {
        try run(limits: options.resourceLimits, policy: .scalarCPU) {
            let parsed = try parse(data, options: options)
            let isDCT = !parsed.frameInfo.isLossless
            let backend = try selectBackend(options.executionPolicy, dct: isDCT)
            let context = NativeOperation(seconds: options.resourceLimits.deadlineSeconds, backend: backend,
                started: NativeOperation.current?.started ?? .now)
            return try NativeOperation.$current.withValue(context) {
                let information = try info(parsed, scale: configuration.scale,
                    sampleFormat: configuration.sampleFormat, decodedOutput: true, options: options)
                let source = information.descriptor
                let descriptor = supplied?.descriptor ?? source
                let plane = try layout(descriptor, allowFloat: configuration.sampleFormat != .nativeInteger, limits: options.resourceLimits)
                guard descriptor.sampleType == source.sampleType, descriptor.width == source.width, descriptor.height == source.height,
                      descriptor.components == source.components, descriptor.meaningfulBits == source.meaningfulBits,
                      descriptor.storageBits >= source.storageBits,
                      descriptor.iccProfile == nil || descriptor.iccProfile == source.iccProfile else {
                    throw CodecError(.incompatibleImageLayout, "Destination does not match JPEG sample interpretation.")
                }
                // Coefficient workspace remains full-frame even for small previews.
                let frame = parsed.frameInfo
                let sampleCount = try checkedMultiply(checkedMultiply(frame.width, frame.height), frame.components.count)
                let workspace = try checkedAdd(checkedAdd(checkedMultiply(data.count, 64), checkedMultiply(sampleCount, isDCT ? 128 : 8)), 1_048_576)
                let metadataSize = try information.metadata.validate(limits: options.resourceLimits, additionalBytes: source.iccProfile?.count ?? 0)
                try admit(workspace: workspace, pixels: supplied?.storage.byteCount ?? descriptor.requiredByteCount,
                          compressed: data.count, metadata: metadataSize, limits: options.resourceLimits)
                try options.progress?(.init(phase: .processing, completedUnits: 0, totalUnits: descriptor.height))
                try NativeOperation.check()
                let destination = try supplied ?? ImageDestination.allocate(descriptor: descriptor, limits: options.resourceLimits)
                let filled = try destination.write { raw in
                    let borrowed = BorrowedSampleDestination(bytes: .init(rebasing: raw[plane.offset...]),
                        rowBytes: plane.rowBytes, bytesPerSample: descriptor.storageBits / 8)
                    if isDCT {
                        let native = JLIDecoderConfiguration(
                            outputPixelFormat: configuration.sampleFormat != .nativeInteger ? .float32 : nil,
                            scale: configuration.scale)
                        _ = try JLIDecoder().decodeParsed(parsed, configuration: native, borrowedDestination: borrowed,
                            normaliseXYBOutput: configuration.sampleFormat == .float32NormalisedSRGB)
                    } else {
                        try JLIDecoder().decodeSharedLossless(parsed, into: borrowed)
                    }
                    try NativeOperation.check()
                }
                let outputDescriptor = try ImageDescriptor(width: descriptor.width, height: descriptor.height,
                    sampleType: descriptor.sampleType, storageBits: descriptor.storageBits, meaningfulBits: descriptor.meaningfulBits,
                    byteOrder: descriptor.byteOrder, components: descriptor.components, colour: descriptor.colour,
                    planes: descriptor.planes, iccProfile: source.iccProfile, limits: options.resourceLimits)
                let image = try Image(descriptor: outputDescriptor, storage: filled.storage,
                                      metadata: information.metadata, limits: options.resourceLimits)
                try options.progress?(.init(phase: .completed, completedUnits: descriptor.height, totalUnits: descriptor.height))
                try NativeOperation.check()
                return DecodedImage(image: image, report: .init(backend: backend,
                    fallbackReason: fallback(options.executionPolicy),
                    fidelity: isDCT ? .lossy : parsed.scans[0].header.successiveApproxLow == 0 ? .exactSamples
                        : .boundedError((1 << parsed.scans[0].header.successiveApproxLow) - 1),
                    pixelAllocationCount: supplied == nil ? 1 : 0,
                    peakPixelBytes: supplied == nil ? descriptor.requiredByteCount : 0,
                    sampleConversion: configuration.sampleFormat == .float32NormalisedSRGB ? .rawSRGBToNormalisedFloat32 : nil,
                    colourConversion: parsed.iccProfile == XYBICCProfile.data ? .xybToSRGB : nil))
            }
        }
    }
}
