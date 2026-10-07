// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Synchronous kernels borrow the operation's cancellation/deadline context.
/// The shared path stays on its invoking task; legacy Dispatch workers are not
/// used here, so the task-local context and cancellation cannot be lost.
struct NativeOperation: Sendable {
    @TaskLocal static var current: NativeOperation?
    let started = ContinuousClock.now
    let seconds: Double
    let backend: Backend
    init(seconds: Double, backend: Backend = .scalarCPU) {
        self.seconds = seconds; self.backend = backend
    }
    static func check() throws {
        try Task.checkCancellation()
        if let context = current, context.started.duration(to: .now) >= .seconds(context.seconds) {
            throw CodecError(.resourceLimitExceeded, "JPEG operation deadline exceeded.")
        }
    }
}

/// Adapter for the migrated SOF3 kernels. Additional native modes are retained
/// internally while their common API storage/fidelity contracts are qualified.
enum JPEGCodec {
    static let capabilities = CodecCapabilities(
        formats: ["JPEG (SOF3)"], compressionModes: [.lossless] +
            (1...15).map { .nearLossless(maximumAbsoluteError: (1 << $0) - 1) },
        sampleTypes: [.unsignedInteger], meaningfulPrecision: 2...16,
        layouts: ["greyscale8", "greyscale16", "rgb8", "rgb16"],
        availableBackends: [.scalarCPU], canInspect: true, canEncode: true, canDecode: true)

    static func run<T>(limits: ResourceLimits, policy: ExecutionPolicy, _ body: () throws -> T) throws -> T {
        try NativeOperation.$current.withValue(NativeOperation(seconds: limits.deadlineSeconds)) {
            try NativeOperation.check()
            if case .required(.accelerated) = policy {
                throw CodecError(.backendUnavailable, "The SOF3 path has no accelerated backend.")
            }
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
        if case .preferred(.accelerated) = policy { return "SOF3 uses the scalar CPU backend." }
        return nil
    }

    static func layout(_ descriptor: ImageDescriptor, limits: ResourceLimits) throws -> PlaneDescriptor {
        try descriptor.validate(limits: limits)
        let grey = descriptor.components == [.grey] && descriptor.colour == .greyscale
        let rgb = descriptor.components == [.red, .green, .blue] && descriptor.colour == .rgb
        guard descriptor.sampleType == .unsignedInteger, descriptor.alpha == .absent,
              grey || rgb, (2...16).contains(descriptor.meaningfulBits),
              descriptor.storageBits == 8 || descriptor.storageBits == 16 else {
            throw CodecError(.unsupportedFeature, "SOF3 requires unsigned greyscale or RGB samples, without alpha.")
        }
        guard descriptor.width <= 65535, descriptor.height <= 65535 else {
            throw CodecError(.unsupportedFeature, "JPEG dimensions exceed the 16-bit frame fields.")
        }
        let bps = descriptor.storageBits / 8
        guard descriptor.planes.count == 1, descriptor.byteOrder == .littleEndian || bps == 1,
              let plane = descriptor.planes.first,
              plane.components == Array(descriptor.components.indices),
              plane.sampleStride == bps, plane.pixelStride == bps * descriptor.components.count else {
            throw CodecError(.incompatibleImageLayout, "SOF3 currently requires interleaved little-endian storage.")
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
        try run(limits: options.resourceLimits, policy: options.executionPolicy) {
            let limits = options.resourceLimits, d = image.descriptor
            let plane = try layout(d, limits: limits)
            let metadataBytes = try image.metadata.validate(limits: limits, additionalBytes: d.iccProfile?.count ?? 0)
            // ICC defines interpretation and is retained even when ancillary data is discarded.
            let keys = options.metadataPolicy == .preserve ? Set(image.metadata.entries.keys) : image.metadata.requiredKeys
            guard keys.isSubset(of: ["Exif"]) else {
                throw CodecError(.unsupportedFeature, "JPEG cannot preserve the requested metadata keys.")
            }
            let exif = keys.contains("Exif") ? image.metadata.entries["Exif"] : nil
            guard (exif?.count ?? 0) <= 65527, (d.iccProfile?.count ?? 0) <= 255 * 65519 else {
                throw CodecError(.unsupportedFeature, "Metadata exceeds JPEG segment capacity.")
            }
            let samples = try checkedMultiply(checkedMultiply(d.width, d.height), d.components.count)
            let outputBound = try checkedAdd(checkedMultiply(samples, 8), checkedAdd(checkedMultiply(metadataBytes, 2), 4096))
            let workspace = try checkedAdd(checkedMultiply(samples, 64), checkedAdd(checkedMultiply(metadataBytes, 4), 1_048_576))
            try admit(workspace: workspace, pixels: image.storage.byteCount, compressed: outputBound,
                      metadata: metadataBytes, limits: limits)
            var cfg = JLIEncoderConfiguration.diagnosticLossless
            cfg.losslessPrecision = d.meaningfulBits
            cfg.losslessPointTransform = configuration.pointTransform(precision: d.meaningfulBits)
            cfg.losslessPredictor = configuration.codecOptions.predictor
            cfg.restartInterval = configuration.codecOptions.restartInterval
            guard cfg.restartInterval == 0 || cfg.restartInterval % d.width == 0 else {
                throw CodecError(.invalidArgument, "Lossless restart interval must contain complete rows.")
            }
            try options.progress?(.init(phase: .processing, completedUnits: 0, totalUnits: d.height))
            let encoded: [UInt8] = try image.storage.withUnsafeBytes { raw in
                guard raw.count == image.storage.byteCount, raw.count >= d.requiredByteCount else {
                    throw CodecError(.storageUnavailable, "Source provider returned inconsistent capacity.")
                }
                let bps = d.storageBits / 8, maxSample = UInt32(1) << d.meaningfulBits
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
            let mode: CompressionMode = errorBound == 0 ? .lossless : .nearLossless(maximumAbsoluteError: errorBound)
            return EncodedImage(data: Data(encoded), encoding: .init(format: "JPEG", mode: mode),
                report: .init(backend: .scalarCPU, fallbackReason: fallback(options.executionPolicy),
                              fidelity: errorBound == 0 ? .exactSamples : .boundedError(errorBound),
                              pixelAllocationCount: 0, peakPixelBytes: 0))
        }
    }

    static func parse(_ data: Data, options: DecodeOptions) throws -> ParsedJPEG {
        let limits = options.resourceLimits
        // Bound copies/table storage before materialising the array or parsing.
        let parserBudget = try checkedAdd(checkedMultiply(data.count, 64), 1_048_576)
        try admit(workspace: parserBudget, pixels: 0, compressed: data.count, metadata: 0, limits: limits)
        let bytes = Array(data)
        try JPEGEnvelope.validate(bytes, limits: limits)
        var reader = MarkerReader(data: bytes)
        let parsed = try reader.parse()
        let f = parsed.frameInfo
        guard f.isLossless else { throw CodecError(.unsupportedFeature, "Common decode currently supports SOF3 JPEG.") }
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

    static func info(_ parsed: ParsedJPEG, options: DecodeOptions) throws -> ImageInfo {
        let f = parsed.frameInfo, nc = f.components.count
        guard (2...16).contains(f.precision), nc == 1 || nc == 3 else {
            throw CodecError(.unsupportedFeature, "Unsupported JPEG precision or component count.")
        }
        // SOF3 has no colour conversion. Accept only explicit RGB identifiers for colour.
        guard nc == 1 || f.components.map(\.id) == [0x52, 0x47, 0x42] else {
            throw CodecError(.unsupportedFeature, "Lossless colour interpretation is ambiguous.")
        }
        let bps = f.precision <= 8 ? 1 : 2
        let row = try checkedMultiply(f.width, nc * bps)
        let capacity = try checkedMultiply(row, f.height)
        let plane = try PlaneDescriptor(width: f.width, height: f.height, components: Array(0..<nc),
            sampleStride: bps, pixelStride: nc * bps, rowBytes: row, byteCount: capacity)
        let descriptor = try ImageDescriptor(width: f.width, height: f.height, storageBits: bps * 8,
            meaningfulBits: f.precision, components: nc == 1 ? [.grey] : [.red, .green, .blue],
            colour: nc == 1 ? .greyscale : .rgb, planes: [plane],
            iccProfile: parsed.iccProfile.map { Data($0) }, limits: options.resourceLimits)
        let metadata = ImageMetadata(entries: options.metadataPolicy == .preserve
            ? parsed.exif.map { ["Exif": Data($0)] } ?? [:] : [:])
        try metadata.validate(limits: options.resourceLimits, additionalBytes: descriptor.iccProfile?.count ?? 0)
        return ImageInfo(format: "JPEG", descriptor: descriptor, frameCount: 1, metadata: metadata)
    }

    static func inspect(_ data: Data, options: DecodeOptions) throws -> ImageInfo {
        try run(limits: options.resourceLimits, policy: options.executionPolicy) {
            let result = try info(parse(data, options: options), options: options)
            try NativeOperation.check()
            return result
        }
    }

    static func decode(_ data: Data, into supplied: ImageDestination?, options: DecodeOptions) throws -> DecodedImage {
        try run(limits: options.resourceLimits, policy: options.executionPolicy) {
            let parsed = try parse(data, options: options)
            let information = try info(parsed, options: options), source = information.descriptor
            let descriptor = supplied?.descriptor ?? source
            let plane = try layout(descriptor, limits: options.resourceLimits)
            guard descriptor.width == source.width, descriptor.height == source.height,
                  descriptor.components == source.components, descriptor.meaningfulBits == source.meaningfulBits,
                  descriptor.storageBits >= source.storageBits,
                  descriptor.iccProfile == nil || descriptor.iccProfile == source.iccProfile else {
                throw CodecError(.incompatibleImageLayout, "Destination does not match JPEG sample interpretation.")
            }
            let sampleCount = try checkedMultiply(checkedMultiply(source.width, source.height), source.components.count)
            let workspace = try checkedAdd(checkedAdd(checkedMultiply(data.count, 64), checkedMultiply(sampleCount, 8)), 1_048_576)
            let metadataSize = try information.metadata.validate(limits: options.resourceLimits, additionalBytes: source.iccProfile?.count ?? 0)
            try admit(workspace: workspace, pixels: supplied?.storage.byteCount ?? descriptor.requiredByteCount,
                      compressed: data.count, metadata: metadataSize, limits: options.resourceLimits)
            try options.progress?(.init(phase: .processing, completedUnits: 0, totalUnits: descriptor.height))
            try NativeOperation.check()
            let destination = try supplied ?? ImageDestination.allocate(descriptor: descriptor, limits: options.resourceLimits)
            let filled = try destination.write { raw in
                try JLIDecoder().decodeSharedLossless(parsed, into: BorrowedSampleDestination(
                    bytes: .init(rebasing: raw[plane.offset...]), rowBytes: plane.rowBytes,
                    bytesPerSample: descriptor.storageBits / 8))
                try NativeOperation.check()
            }
            let outputDescriptor = try ImageDescriptor(width: descriptor.width, height: descriptor.height,
                storageBits: descriptor.storageBits, meaningfulBits: descriptor.meaningfulBits,
                byteOrder: descriptor.byteOrder, components: descriptor.components, colour: descriptor.colour,
                planes: descriptor.planes, iccProfile: source.iccProfile, limits: options.resourceLimits)
            let image = try Image(descriptor: outputDescriptor, storage: filled.storage,
                                  metadata: information.metadata, limits: options.resourceLimits)
            try options.progress?(.init(phase: .completed, completedUnits: descriptor.height, totalUnits: descriptor.height))
            try NativeOperation.check()
            return DecodedImage(image: image, report: .init(backend: .scalarCPU,
                fallbackReason: fallback(options.executionPolicy),
                fidelity: parsed.scans[0].header.successiveApproxLow == 0 ? .exactSamples
                    : .boundedError((1 << parsed.scans[0].header.successiveApproxLow) - 1),
                pixelAllocationCount: supplied == nil ? 1 : 0,
                peakPixelBytes: supplied == nil ? descriptor.requiredByteCount : 0))
        }
    }
}
