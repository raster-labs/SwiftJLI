// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.

#if canImport(Accelerate)
import Accelerate
#endif
import Foundation

/// The jpegli-compatible JPEG decoder.
///
/// `JLIDecoder` decompresses JPEG data, automatically detecting advanced features
/// such as jpegli 10+ bit precision and XYB color space encoding.
///
/// Supports baseline sequential JPEG (SOF0) with standard Huffman coding and all
/// chroma subsampling modes. Progressive JPEG (SOF2) parsing is supported but
/// full progressive decoding is planned for a future milestone.
///
/// ## Usage
///
/// ```swift
/// let decoder = JLIDecoder()
/// let info = try decoder.inspect(data: jpegBytes)
/// let image = try decoder.decode(from: jpegBytes)
/// ```
struct JLIDecoder: Sendable {
    /// Creates a new decoder instance.
    init() {}

    /// Inspects JPEG data and returns metadata without fully decoding the image.
    ///
    /// Use this to detect whether a JPEG uses advanced jpegli features (10+ bit,
    /// XYB color space) before deciding on a decode configuration.
    ///
    /// - Parameter data: The JPEG bitstream bytes.
    /// - Returns: A ``JLIJPEGInfo`` describing the JPEG's properties.
    /// - Throws: ``JLIError`` if the data is not valid JPEG.
    func inspect(data: [UInt8]) throws -> JLIJPEGInfo {
        guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
            throw JLIError.invalidJPEGData
        }
        var reader = MarkerReader(data: data)
        return try reader.readInfo()
    }

    /// Decodes JPEG data into a ``JLIImage``.
    ///
    /// The decoder automatically detects jpegli-specific features:
    /// - **10+ bit precision**: Outputs to a 16-bit buffer unless overridden.
    /// - **XYB color space**: Applies the correct inverse transform.
    ///
    /// - Parameters:
    ///   - data: The JPEG bitstream bytes.
    ///   - configuration: Decoder settings controlling output format.
    /// - Returns: The decoded image.
    /// - Throws: ``JLIError`` if decoding fails.
    func decode(
        from data: [UInt8],
        configuration: JLIDecoderConfiguration = .default
    ) throws -> JLIImage {
        guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
            throw JLIError.invalidJPEGData
        }

        // Step 1: Parse JPEG markers
        var markerReader = MarkerReader(data: data)
        let parsed = try markerReader.parse()
        return try decodeParsed(parsed, configuration: configuration)
    }

    func decodeParsed(_ parsed: ParsedJPEG, configuration: JLIDecoderConfiguration = .default,
                      borrowedDestination: BorrowedSampleDestination? = nil, normaliseXYBOutput: Bool = false,
                      useScalarCEntropy: Bool = false) throws -> JLIImage {
        let frame = parsed.frameInfo

        guard !parsed.scans.isEmpty else {
            throw JLIError.decodingFailed("No scan data found in JPEG")
        }

        // Lossless (SOF3) is predictive, not DCT — fully separate path.
        if frame.isLossless {
            return try decodeLossless(frame: frame, scans: parsed.scans, configuration: configuration,
                                      restartInterval: parsed.restartInterval,
                                      iccProfile: parsed.iccProfile, exif: parsed.exif,
                                      useScalarCEntropy: useScalarCEntropy)
        }

        // Step 2: Prepare quantization tables (convert from zigzag to natural order)
        let quantTables = parsed.quantTables.map { zigzagTable -> [Int] in
            var natural = [Int](repeating: 0, count: 64)
            for i in 0..<64 {
                natural[Quantization.zigzagOrder[i]] = zigzagTable[i]
            }
            return natural
        }

        // Reject structurally-invalid frames before any size math or indexing.
        try validateDecodable(frame, quantTableCount: quantTables.count)

        // Reduced-scale (thumbnail) decode. 1 = full; 2/4 = low-freq box average;
        // 8 = 1/8 (DC-only). Each output sample is the exact mean of its
        // scale×scale source box, formed directly from the DCT coefficients.
        let scale = configuration.scale
        guard scale == 1 || scale == 2 || scale == 4 || scale == 8 else {
            throw JLIError.unsupportedJPEGFeature("decode scale \(scale) (only 1, 2, 4, 8 supported)")
        }

        // Step 3: Determine MCU structure
        let components = frame.components
        let numComponents = components.count
        let hMaxSampling = components.map(\.horizontalSampling).max() ?? 1
        let vMaxSampling = components.map(\.verticalSampling).max() ?? 1
        let mcuW = hMaxSampling * 8
        let mcuH = vMaxSampling * 8
        let mcuCountH = (frame.width + mcuW - 1) / mcuW
        let mcuCountV = (frame.height + mcuH - 1) / mcuH

        // Admission and dispatch share this decision, including the bounded
        // coefficient/scratch capacity. Unsupported paths retain full planes.
        let streamingPlan = try SequentialGreyscalePlan.make(parsed: parsed, configuration: configuration,
            hasDestination: borrowedDestination != nil, normaliseXYBOutput: normaliseXYBOutput,
            workerLimit: NativeOperation.current?.maximumWorkers ?? NativeOperation.workerLimit,
            backend: NativeOperation.current?.backend ?? (NativeDSP.usesAccelerate ? .accelerated : .scalarCPU))
        let directGreyscale = scale == 1 && numComponents == 1 && NativeOperation.workerLimit == 1
            && !parsed.isXYB && !parsed.isRawRGB && !normaliseXYBOutput
            && configuration.outputColorModel == nil
            && (configuration.outputPixelFormat == nil || configuration.outputPixelFormat == .float32)
        let floating = configuration.outputPixelFormat == .float32
        if let streamingPlan, let borrowedDestination {
            let scan = parsed.scans[0]
            let selector = scan.header.components.first { $0.componentSelector == components[0].id }
            let dcTable = prepareDCTables(scan.dcTables)[selector?.dcTableId ?? 0] ?? StandardHuffmanTables.dcLuminance
            let acTable = prepareACTables(scan.acTables)[selector?.acTableId ?? 0] ?? StandardHuffmanTables.acLuminance
            var reader = BitReader(data: scan.entropyData)
            if streamingPlan.dcOnlyTable {
                try Self.validateGreyscaleDestination(borrowedDestination, width: frame.width,
                    height: frame.height, precision: frame.precision, floatOutput: floating)
                try DCOnlyGreyscaleDecoder.decodeInto(reader: &reader, dcTable: dcTable, acTable: acTable,
                    quantiser: Float(quantTables[components[0].quantTableIndex][0]), plan: streamingPlan,
                    width: frame.width, height: frame.height, precision: frame.precision,
                    restartInterval: parsed.restartInterval, floatOutput: floating, destination: borrowedDestination)
            } else {
                // Lookup admission uses the entire scan, as in the retained path.
                let lookup = ACLookahead(table: acTable, blockCount: streamingPlan.blockCount)
                try Self.decodeSequentialGreyscaleInto(reader: &reader, dcTable: dcTable,
                    acTable: acTable, lookup: lookup,
                    quantTable: quantTables[components[0].quantTableIndex].map { Float($0) },
                    plan: streamingPlan,
                    width: frame.width, height: frame.height, precision: frame.precision,
                    restartInterval: parsed.restartInterval, floatOutput: floating, destination: borrowedDestination)
            }
            return try JLIImage(geometryOnlyWidth: frame.width, height: frame.height,
                pixelFormat: floating ? .float32 : frame.precision > 8 ? .uint16 : .uint8,
                colorModel: .grayscale, iccProfile: parsed.iccProfile, exif: parsed.exif)
        }

        // Step 4: Allocate one flat zigzag-coefficient buffer per component.
        // Block `b` of component `c` lives at `componentZigzag[c][b*64 ..< (b+1)*64]`.
        var componentZigzag = [[Int32]]()
        var componentBlocksPerRow = [Int]()
        var componentDimensions = [(blocksH: Int, blocksV: Int)]()
        for comp in components {
            let blocksH = mcuCountH * comp.horizontalSampling
            let blocksV = mcuCountV * comp.verticalSampling
            componentBlocksPerRow.append(blocksH)
            componentDimensions.append((blocksH, blocksV))
            componentZigzag.append([Int32](repeating: 0, count: blocksH * blocksV * 64))
        }

        // Step 5: Decode entropy data into the flat per-component buffers.
        // Progressive (SOF2) uses multiple scans with spectral selection and
        // successive approximation; baseline/extended-sequential uses one scan.
        if frame.isProgressive {
            // Non-interleaved (AC) scans address each component's own data-unit
            // grid: ceil(compW/8) × ceil(compH/8), where compW/H = the component's
            // dimensions after subsampling. Smaller than the MCU-padded grid for
            // images that aren't a whole number of MCUs.
            let realW = components.map { comp -> Int in
                let compW = (frame.width * comp.horizontalSampling + hMaxSampling - 1) / hMaxSampling
                return (compW + 7) / 8
            }
            let realH = components.map { comp -> Int in
                let compH = (frame.height * comp.verticalSampling + vMaxSampling - 1) / vMaxSampling
                return (compH + 7) / 8
            }
            var prog = ProgressiveDecoder(
                components: components,
                mcuCountH: mcuCountH, mcuCountV: mcuCountV,
                blocksPerRow: componentBlocksPerRow,
                blocksPerCol: componentDimensions.map { $0.blocksV },
                realBlocksW: realW, realBlocksH: realH,
                restartInterval: parsed.restartInterval
            )
            try prog.decode(scans: parsed.scans)
            componentZigzag = prog.coeffs
        } else {
            let scan = parsed.scans[0]
            // Use the Huffman table snapshot active at SOS rather than the final merged
            // parser dictionaries, matching JPEGCodec.validateDCT when later DHT segments follow.
            let dcTables = prepareDCTables(scan.dcTables)
            let acTables = prepareACTables(scan.acTables)
            var bitReader = BitReader(data: scan.entropyData)
            var prevDC = [Int32](repeating: 0, count: numComponents)

            let restartInterval = parsed.restartInterval
            var mcuCount = 0
            var restartIndex = 0

            // Tables are fixed per scan — resolve them once per component
            // instead of re-running a closure search + two Dictionary lookups
            // (and the resulting HuffmanTable struct copies) on every MCU.
            let compDCTables: [HuffmanTable] = components.map { comp in
                let sc = scan.header.components.first { $0.componentSelector == comp.id }
                return dcTables[sc?.dcTableId ?? 0] ?? StandardHuffmanTables.dcLuminance
            }
            let compACTables: [HuffmanTable] = components.map { comp in
                let sc = scan.header.components.first { $0.componentSelector == comp.id }
                return acTables[sc?.acTableId ?? 0] ?? StandardHuffmanTables.acLuminance
            }
            let compACLookups = compACTables.enumerated().map { index, table in
                ACLookahead(table: table, blockCount: componentZigzag[index].count / 64)
            }

            if numComponents == 1, components[0].horizontalSampling == 1,
               components[0].verticalSampling == 1 {
                try componentZigzag[0].withUnsafeMutableBufferPointer { coefficients in
                    try SequentialGreyscaleDecoder.decode(
                        reader: &bitReader, dcTable: compDCTables[0], acTable: compACTables[0],
                        lookup: compACLookups[0], coefficients: coefficients,
                        blocksPerRow: mcuCountH, blockRows: mcuCountV,
                        precision: frame.precision, restartInterval: restartInterval)
                }
            } else {
                for mcuY in 0..<mcuCountV {
                    try NativeOperation.check()
                    for mcuX in 0..<mcuCountH {
                        // Every `restartInterval` MCUs, skip the RST0–RST7 marker
                        // (cycled) and reset DC predictors.
                        if restartInterval > 0 && mcuCount > 0
                            && mcuCount % restartInterval == 0 {
                            try bitReader.skipRestartMarker(expectedIndex: restartIndex)
                            restartIndex = (restartIndex + 1) & 7
                            for i in 0..<numComponents { prevDC[i] = 0 }
                        }
                        mcuCount += 1

                        for compIdx in 0..<numComponents {
                            let comp = components[compIdx]
                            let dcTable = compDCTables[compIdx]
                            let acTable = compACTables[compIdx]
                            let blocksPerRow = componentBlocksPerRow[compIdx]

                            for by in 0..<comp.verticalSampling {
                                for bx in 0..<comp.horizontalSampling {
                                    let blockX = mcuX * comp.horizontalSampling + bx
                                    let blockY = mcuY * comp.verticalSampling + by
                                    let blockIndex = blockY * blocksPerRow + blockX
                                    let dst = blockIndex * 64

                                    let dcDiff = try HuffmanDecoder.decodeDC(
                                        from: &bitReader, table: dcTable
                                    )
                                    let dc = Int64(prevDC[compIdx]) + Int64(dcDiff)
                                    guard abs(dc) <= (1 << (frame.precision + 2)) else {
                                        throw JLIError.decodingFailed("DC coefficient exceeds sample precision")
                                    }
                                    prevDC[compIdx] = Int32(dc)

                                    // Decode directly into the coefficient plane.
                                    // One scoped borrow replaces per-coefficient
                                    // array uniqueness checks and a block copy.
                                    try componentZigzag[compIdx].withUnsafeMutableBufferPointer { zz in
                                        let block = UnsafeMutableBufferPointer(rebasing: zz[dst..<(dst + 64)])
                                        if let lookup = compACLookups[compIdx] {
                                            try HuffmanDecoder.decodeAC(from: &bitReader, table: acTable, lookup: lookup, into: block)
                                        } else {
                                            try HuffmanDecoder.decodeAC(from: &bitReader, table: acTable, into: block)
                                        }
                                        block[0] = prevDC[compIdx]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // A single-worker greyscale decode needs no full-frame Float plane:
        // each unchanged 1024-block IDCT batch can be rounded into its final
        // destination immediately. All destination writes stay on this caller
        // thread, inside the owning storage borrow; no worker receives it.
        if directGreyscale, let borrowedDestination {
            try Self.reconstructGreyscaleInto(componentZigzag[0],
                quantTable: quantTables[components[0].quantTableIndex].map { Float($0) },
                blocksPerRow: componentDimensions[0].blocksH,
                width: frame.width, height: frame.height, precision: frame.precision,
                floatOutput: floating, destination: borrowedDestination)
            return try JLIImage(geometryOnlyWidth: frame.width, height: frame.height,
                pixelFormat: floating ? .float32 : frame.precision > 8 ? .uint16 : .uint8,
                colorModel: .grayscale, iccProfile: parsed.iccProfile, exif: parsed.exif)
        }

        // Step 7: Per component — fused dequantize+IDCT straight from the
        // entropy-order coefficients, level-shift, then write each block into
        // its (exactly component-sized) plane — in parallel across block ranges
        // for large images (every 8×8 block writes a disjoint plane tile, so
        // any block partition is race-free and the result is bit-identical to
        // a serial pass; gated by ``reconstructMinBlocksPerChunk`` and proven
        // by `parallelDecodeDeterministic`).
        var componentPlanes = [(data: [Float], width: Int, height: Int)]()
        let maxBlockCount = componentDimensions.map { $0.blocksH * $0.blocksV }.max() ?? 0
        let coefficientCount = maxBlockCount * 64
        // The separate inverse-zigzag + dequantize buffers are only needed by
        // the 1/2 & 1/4 box-average preview path; the full-resolution path
        // fuses both into the IDCT pack pass.
        let needsNatural = scale == 2 || scale == 4
        // Do not run unsafeUninitializedCapacity with zero capacity: Swift
        // 6.2's finaliser writes the shared empty-array singleton's count,
        // producing a race between otherwise independent decoders under TSan.
        // Choosing [] before entering that initialiser avoids the shared write.
        var natural: [Int32] = needsNatural
            ? [Int32](unsafeUninitializedCapacity: coefficientCount) { _, count in count = coefficientCount } : []
        var dctBuf: [Float] = needsNatural
            ? [Float](unsafeUninitializedCapacity: coefficientCount) { _, count in count = coefficientCount } : []

        for compIdx in 0..<numComponents {
            let comp = components[compIdx]
            let blocksH = componentDimensions[compIdx].blocksH
            let blocksV = componentDimensions[compIdx].blocksV
            let blockCount = blocksH * blocksV
            let qtF = quantTables[comp.quantTableIndex].map { Float($0) }

            let compWidth = (frame.width * comp.horizontalSampling + hMaxSampling - 1) / hMaxSampling
            let compHeight = (frame.height * comp.verticalSampling + vMaxSampling - 1) / vMaxSampling

            // 1/8 DC-only path: each 8×8 block reduces to one pixel — its average,
            // which for the normalized DCT is (1/8)·dequant(DC) + level shift. No
            // inverse DCT; output plane is the block grid, trimmed to ceil(comp/8).
            if scale == 8 {
                let center = Float(1 << (frame.precision - 1))
                let maxV = Float((1 << frame.precision) - 1)
                let dcStep = Float(quantTables[comp.quantTableIndex][0])  // DC quant (natural order)
                var small = [Float](repeating: 0, count: blocksH * blocksV)
                try componentZigzag[compIdx].withUnsafeBufferPointer { src in
                    for b in 0..<blockCount {
                        if b % 1024 == 0 { try NativeOperation.check() }
                        let dc = Float(src[b * 64]) * dcStep
                        small[b] = min(max(dc * (1.0 / 8.0) + center, 0), maxV)
                    }
                }
                let cwS = (compWidth + 7) / 8
                let chS = (compHeight + 7) / 8
                if blocksH != cwS || blocksV != chS {
                    var trimmed = [Float](repeating: 0, count: cwS * chS)
                    for y in 0..<chS {
                        for x in 0..<cwS { trimmed[y * cwS + x] = small[y * blocksH + x] }
                    }
                    componentPlanes.append((trimmed, cwS, chS))
                } else {
                    componentPlanes.append((small, blocksH, blocksV))
                }
                continue
            }

            // 1/2 & 1/4 box-average path: each 8×8 block reduces to a bs×bs tile
            // (bs = 8/scale) whose samples are the exact means of the scale×scale
            // source-pixel boxes, formed straight from the coefficients via the
            // separable A·F·Aᵀ contraction (A = ``boxAverageMatrix``). No IDCT.
            // This preview path keeps the separate inverse-zigzag + dequantize
            // passes (the contraction reads natural-order coefficients).
            if scale == 2 || scale == 4 {
                let zigzag = Quantization.zigzagOrder
                try componentZigzag[compIdx].withUnsafeBufferPointer { srcBuf in
                    try natural.withUnsafeMutableBufferPointer { dstBuf in
                        let src = srcBuf.baseAddress!
                        let dst = dstBuf.baseAddress!
                        for b in 0..<blockCount {
                            if b % 1024 == 0 { try NativeOperation.check() }
                            let base = b * 64
                            for i in 0..<64 { dst[base + zigzag[i]] = src[base + i] }
                        }
                    }
                }
                if NativeOperation.current != nil {
                    for base in stride(from: 0, to: blockCount, by: 1024) {
                        try NativeOperation.check()
                        let end = min(base + 1024, blockCount), range = (base * 64)..<(end * 64)
                        var output = [Float](repeating: 0, count: range.count)
                        AccelerateDSP.dequantizeBatch(Array(natural[range]), table: qtF, into: &output, blockCount: end - base)
                        dctBuf.replaceSubrange(range, with: output)
                    }
                } else {
                    AccelerateDSP.dequantizeBatch(natural, table: qtF, into: &dctBuf, blockCount: blockCount)
                }
                let bs = 8 / scale
                let a = Self.boxAverageMatrix(scale: scale)        // bs×8, row-major
                let pw = blocksH * bs, ph = blocksV * bs
                var plane = [Float](repeating: 0, count: pw * ph)
                let center = Float(1 << (frame.precision - 1))
                let maxV = Float((1 << frame.precision) - 1)
                try dctBuf.withUnsafeBufferPointer { fb in
                    try plane.withUnsafeMutableBufferPointer { pb in
                        let f = fb.baseAddress!
                        var tmp = [Float](repeating: 0, count: bs * 8)   // tmp[J*8+u]
                        for b in 0..<blockCount {
                            if b % 1024 == 0 { try NativeOperation.check() }
                            let base = b * 64
                            // tmp[J,u] = Σ_v A[J,v]·F[v*8+u]
                            for j in 0..<bs {
                                for u in 0..<8 {
                                    var acc: Float = 0
                                    for v in 0..<8 { acc += a[j * 8 + v] * f[base + v * 8 + u] }
                                    tmp[j * 8 + u] = acc
                                }
                            }
                            let blockX = (b % blocksH) * bs
                            let blockY = (b / blocksH) * bs
                            for j in 0..<bs {
                                let py = blockY + j
                                if py >= ph { break }
                                let rowBase = py * pw
                                for i in 0..<bs {
                                    let px = blockX + i
                                    if px >= pw { break }
                                    // out[i,j] = Σ_u A[i,u]·tmp[J,u]
                                    var acc: Float = 0
                                    for u in 0..<8 { acc += a[i * 8 + u] * tmp[j * 8 + u] }
                                    pb[rowBase + px] = min(max(acc + center, 0), maxV)
                                }
                            }
                        }
                    }
                }
                let cwS = (compWidth + scale - 1) / scale
                let chS = (compHeight + scale - 1) / scale
                if pw != cwS || ph != chS {
                    var trimmed = [Float](repeating: 0, count: cwS * chS)
                    for y in 0..<chS {
                        for x in 0..<cwS { trimmed[y * cwS + x] = plane[y * pw + x] }
                    }
                    componentPlanes.append((trimmed, cwS, chS))
                } else {
                    componentPlanes.append((plane, pw, ph))
                }
                continue
            }

            // Full-resolution path: fused dequant+IDCT per block range, scattered
            // straight into an exactly component-sized plane (no padded plane,
            // no trim copy — edge blocks write only their in-bounds rows/columns,
            // and every in-bounds pixel belongs to some block, so the
            // uninitialized plane is fully covered). Each joined worker owns
            // one bounded scratch slot, reused after each 1024-block batch.
            var plane = [Float](unsafeUninitializedCapacity: compWidth * compHeight) {
                _, c in c = compWidth * compHeight
            }
            let batchBlocks = 1024
            let batchCount = (blockCount - 1) / batchBlocks + 1
            let chunks = min(batchCount, min(NativeOperation.workerLimit,
                             max(1, blockCount / JLIDecoder.reconstructMinBlocksPerChunk)))
            let scratchStride = min(batchBlocks, blockCount) * 64
            // Every used slot is fully written before being read. Bounded
            // slots replace two full-frame arrays. Partition whole global
            // batches: vDSP can change floating-point rounding with matrix
            // dimensions, so workers must retain the serial pass's boundaries
            // and final batch size, including for exact Float32 output.
            let scratchCount = chunks * scratchStride
            var pixelsBuf = [Float](unsafeUninitializedCapacity: scratchCount) { _, c in c = scratchCount }
            var idctScratch = [Float](unsafeUninitializedCapacity: scratchCount) { _, c in c = scratchCount }
            try componentZigzag[compIdx].withUnsafeBufferPointer { zzb in
                try qtF.withUnsafeBufferPointer { qtb in
                    try pixelsBuf.withUnsafeMutableBufferPointer { pxb in
                        try idctScratch.withUnsafeMutableBufferPointer { scb in
                            try plane.withUnsafeMutableBufferPointer { plb in
                                let ptrs = ReconstructPtrs(
                                    zz: zzb.baseAddress!, qt: qtb.baseAddress!,
                                    px: pxb.baseAddress!, scratch: scb.baseAddress!,
                                    plane: plb.baseAddress!)
                                if chunks <= 1 {
                                    for base in stride(from: 0, to: blockCount, by: batchBlocks) {
                                        try NativeOperation.check()
                                        JLIDecoder.reconstructBlocks(
                                            base..<min(base + batchBlocks, blockCount), ptrs: ptrs, blocksH: blocksH,
                                            compWidth: compWidth, compHeight: compHeight,
                                            precision: frame.precision, scratchOffset: 0)
                                    }
                                } else {
                                    try NativeOperation.perform(iterations: chunks) { c in
                                        for batch in stride(from: c, to: batchCount, by: chunks) {
                                            try NativeOperation.check()
                                            let base = batch * batchBlocks
                                            JLIDecoder.reconstructBlocks(
                                                base..<min(base + batchBlocks, blockCount), ptrs: ptrs, blocksH: blocksH,
                                                compWidth: compWidth, compHeight: compHeight,
                                                precision: frame.precision, scratchOffset: c * scratchStride)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            componentPlanes.append((plane, compWidth, compHeight))
        }

        // Step 8: Chroma upsample and color convert. Output dimensions are the
        // image dimensions reduced by `scale` (= full dims when scale == 1).
        let outW = (frame.width + scale - 1) / scale
        let outH = (frame.height + scale - 1) / scale
        // Full-resolution integer YCbCr uses SOF sample centres and component
        // rounding. Prepare the planes once for both final-storage writers;
        // 4:4:4, previews, raw Float32, greyscale and XYB keep their existing
        // semantics. The established 4:4:4 oracle has a tighter error bound.
        if scale == 1, numComponents == 3, configuration.outputPixelFormat != .float32,
           !parsed.isXYB, !parsed.isRawRGB,
           components.contains(where: { $0.horizontalSampling != hMaxSampling || $0.verticalSampling != vMaxSampling }) {
            for index in componentPlanes.indices {
                let plane = componentPlanes[index]
                componentPlanes[index] = (try ChromaSampling.upsampleJPEG(
                    plane.data, width: plane.width, height: plane.height,
                    targetWidth: outW, targetHeight: outH,
                    horizontalSampling: components[index].horizontalSampling,
                    verticalSampling: components[index].verticalSampling,
                    maximumHorizontalSampling: hMaxSampling,
                    maximumVerticalSampling: vMaxSampling), outW, outH)
            }
        }
        if let borrowedDestination {
            let floating = configuration.outputPixelFormat == .float32
            let xyb = parsed.isXYB
            guard !normaliseXYBOutput || (xyb && floating),
                  configuration.outputPixelFormat == nil || (floating && (numComponents == 1 || normaliseXYBOutput)),
                  configuration.outputColorModel == nil,
                  !xyb || !floating || normaliseXYBOutput,
                  (!floating || borrowedDestination.bytesPerSample == 4) else {
                throw JLIError.unsupportedJPEGFeature("Unsupported borrowed DCT output")
            }
            try SharedDCTStorage.write(componentPlanes, width: outW, height: outH,
                precision: frame.precision, floatOutput: floating, xyb: parsed.isXYB,
                rawRGB: parsed.isRawRGB, into: borrowedDestination)
            return try JLIImage(geometryOnlyWidth: outW, height: outH,
                pixelFormat: floating ? .float32 : frame.precision > 8 ? .uint16 : .uint8,
                colorModel: numComponents == 1 ? .grayscale : .rgb,
                iccProfile: parsed.iccProfile, exif: parsed.exif)
        }
        let outputData: [UInt8]
        let outputColorModel: JLIColorModel
        // 12-bit (grayscale or color) decodes to a uint16 buffer (little-endian
        // samples); 8-bit stays uint8.
        let isExtendedPrecision = frame.precision > 8

        // Float32 output: emit the reconstructed sample planes as 32-bit
        // little-endian floats — the RAW sample values (e.g. 0…4095 for 12-bit),
        // NOT normalized to [0,1] (that asymmetry vs the encoder's float32 *input*
        // is intentional; see JLIDecoderConfiguration.outputPixelFormat). This is
        // a zero-rounding passthrough of the same float planes the integer path
        // rounds, so it never loses precision. Grayscale and XYB are supported;
        // the YCbCr→RGB path is not (its integer helper does not expose floats).
        let wantsFloat32 = configuration.outputPixelFormat == .float32

        if numComponents == 1 {
            // Grayscale
            let plane = componentPlanes[0]
            if wantsFloat32 {
                outputData = Self.floatsToLE(plane.data)
            } else if isExtendedPrecision {
                var bytes = [UInt8](repeating: 0, count: plane.data.count * 2)
                for i in 0..<plane.data.count {
                    let v = UInt16(clamping: Int(plane.data[i].rounded()))
                    bytes[i * 2] = UInt8(v & 0xFF)
                    bytes[i * 2 + 1] = UInt8(v >> 8)
                }
                outputData = bytes
            } else {
                outputData = plane.data.map { UInt8(clamping: Int($0.rounded())) }
            }
            outputColorModel = configuration.outputColorModel ?? .grayscale
        } else if parsed.isRawRGB {
            let bps = wantsFloat32 ? 4 : isExtendedPrecision ? 2 : 1
            var bytes = [UInt8](repeating: 0, count: outW * outH * 3 * bps)
            try bytes.withUnsafeMutableBytes { raw in
                try SharedDCTStorage.write(componentPlanes, width: outW, height: outH,
                    precision: frame.precision, floatOutput: wantsFloat32, rawRGB: true,
                    into: .init(bytes: raw, rowBytes: outW * 3 * bps, bytesPerSample: bps))
            }
            outputData = bytes
            outputColorModel = .rgb
        } else if numComponents == 3 && !isExtendedPrecision
                    && parsed.isXYB {
            // XYB color: the three full-resolution planes are scaled-XYB samples
            // (4:4:4). Invert the XYB transform per pixel to recover sRGB. (The
            // embedded ICC also lets non-XYB-aware decoders display it.)
            func trim(_ p: (data: [Float], width: Int, height: Int)) -> [Float] {
                if p.width == outW && p.height == outH { return p.data }
                var t = [Float](repeating: 0, count: outW * outH)
                for y in 0..<outH { for x in 0..<outW { t[y * outW + x] = p.data[y * p.width + x] } }
                return t
            }
            let xs = trim(componentPlanes[0]), ys = trim(componentPlanes[1]), bs = trim(componentPlanes[2])
            if wantsFloat32 {
                var rgbF = [Float](repeating: 0, count: outW * outH * 3)
                for i in 0..<(outW * outH) {
                    let (r, g, b) = ColorConversion.xybSampleToRGB(x: xs[i], y: ys[i], bChannel: bs[i])
                    rgbF[i * 3] = r; rgbF[i * 3 + 1] = g; rgbF[i * 3 + 2] = b
                }
                outputData = Self.floatsToLE(rgbF)
            } else {
                var rgb = [UInt8](repeating: 0, count: outW * outH * 3)
                for i in 0..<(outW * outH) {
                    let (r, g, b) = ColorConversion.xybSampleToRGB(x: xs[i], y: ys[i], bChannel: bs[i])
                    rgb[i * 3] = UInt8(clamping: Int(r.rounded()))
                    rgb[i * 3 + 1] = UInt8(clamping: Int(g.rounded()))
                    rgb[i * 3 + 2] = UInt8(clamping: Int(b.rounded()))
                }
                outputData = rgb
            }
            outputColorModel = configuration.outputColorModel ?? .rgb
        } else {
            // YCbCr → RGB
            guard !wantsFloat32 else {
                // The YCbCr→RGB conversion runs through an integer-output vDSP
                // helper; a float path here would duplicate that math and risk
                // diverging from the integer path's rounding. Float32 decode is
                // supported for grayscale and XYB only for now.
                throw JLIError.unsupportedJPEGFeature(
                    "float32 output for YCbCr color (supported for grayscale and XYB)")
            }
            let yPlane = componentPlanes[0]

            // Upsample Cb and Cr to full resolution
            let cbUp = try ChromaSampling.upsample(
                componentPlanes[1].data,
                width: componentPlanes[1].width,
                height: componentPlanes[1].height,
                targetWidth: outW, targetHeight: outH
            )
            let crUp = try ChromaSampling.upsample(
                componentPlanes[2].data,
                width: componentPlanes[2].width,
                height: componentPlanes[2].height,
                targetWidth: outW, targetHeight: outH
            )

            // Trim Y plane if padded
            let yTrimmed: [Float]
            if yPlane.width != outW || yPlane.height != outH {
                var trimmed = [Float](repeating: 0, count: outW * outH)
                for y in 0..<outH {
                    for x in 0..<outW {
                        trimmed[y * outW + x] = yPlane.data[y * yPlane.width + x]
                    }
                }
                yTrimmed = trimmed
            } else {
                yTrimmed = yPlane.data
            }

            if isExtendedPrecision {
                // 12-bit color → little-endian UInt16 RGB. Planes are already
                // reconstructed in 0...2^P-1 with chroma centered at 2^(P-1).
                outputData = ColorConversion.imageYCbCr16ToRGB(
                    y: yTrimmed, cb: cbUp, cr: crUp,
                    width: outW, height: outH,
                    center: Float(1 << (frame.precision - 1)),
                    maxValue: Float((1 << frame.precision) - 1)
                )
            } else {
                outputData = ColorConversion.imageYCbCrToRGB(
                    y: yTrimmed, cb: cbUp, cr: crUp,
                    width: outW, height: outH
                )
            }
            outputColorModel = configuration.outputColorModel ?? .rgb
        }

        let outputPixelFormat = configuration.outputPixelFormat
            ?? (isExtendedPrecision ? .uint16 : .uint8)

        return try JLIImage(
            width: outW,
            height: outH,
            pixelFormat: outputPixelFormat,
            colorModel: outputColorModel,
            data: outputData,
            iccProfile: parsed.iccProfile,
            exif: parsed.exif
        )
    }

    // MARK: - Lossless (SOF3) decode

    /// Decodes a lossless (SOF3) JPEG by spatial prediction (ITU-T T.81 Annex H):
    /// each sample is predicted from already-decoded neighbours (selector 1–7 in
    /// the SOS `spectralStart`), and the Huffman-coded difference (DC mechanism,
    /// SSSS=16 ⇒ −32768 special case) is added back. Grayscale (1) or RGB (3,
    /// stored directly — no color transform, like libjpeg-turbo's lossless).
    private func decodeLossless(
        frame: JPEGFrameInfo, scans: [JPEGScanData], configuration: JLIDecoderConfiguration,
        restartInterval: Int = 0, iccProfile: [UInt8]? = nil, exif: [UInt8]? = nil,
        borrowedDestination: BorrowedSampleDestination? = nil, useScalarCEntropy: Bool = false
    ) throws -> JLIImage {
        let precision = frame.precision
        guard (2...16).contains(precision) else {
            throw JLIError.unsupportedJPEGFeature("lossless precision \(precision)")
        }
        // Lossless reconstructs exact integer samples; a float32 request here would
        // only be a lossy-looking convenience cast and is rejected so callers get
        // the bit-exact uint path (which already preserves every value exactly).
        guard configuration.outputPixelFormat != .float32 else {
            throw JLIError.unsupportedJPEGFeature(
                "float32 output for lossless (use the bit-exact .uint8/.uint16 output)")
        }
        let w = frame.width, h = frame.height
        guard w >= 1, h >= 1, w <= 65535, h <= 65535 else {
            throw JLIError.decodingFailed("invalid lossless dimensions \(w)×\(h)")
        }
        // Decompression-bomb guard: a tiny SOF can declare dimensions whose product
        // would force a multi-gigabyte plane allocation (an uncatchable OOM trap).
        // Cap total samples before allocating. See `maxDecodablePixels`.
        guard w * h <= JLIDecoder.maxDecodablePixels else {
            throw JLIError.decodingFailed(
                "lossless image too large: \(w)×\(h) exceeds \(JLIDecoder.maxDecodablePixels)-pixel limit")
        }
        let nc = frame.components.count
        guard nc == 1 || nc == 3 else {
            throw JLIError.unsupportedJPEGFeature("lossless \(nc)-component (only 1 or 3)")
        }
        for c in frame.components where c.horizontalSampling != 1 || c.verticalSampling != 1 {
            throw JLIError.unsupportedJPEGFeature("subsampled lossless")
        }
        guard let scan = scans.first else { throw JLIError.decodingFailed("no lossless scan") }
        let predictor = scan.header.spectralStart       // 1–7
        let pt = scan.header.successiveApproxLow         // point transform
        guard (1...7).contains(predictor) else {
            throw JLIError.decodingFailed("invalid lossless predictor \(predictor)")
        }
        // The point transform shifts the initial predictor by `precision-1-pt`; a
        // pt ≥ precision yields a negative shift count, which traps at runtime.
        // T.81 also constrains Pt < P for lossless. Reject out-of-range values
        // (a 4-bit Al field can carry 0–15) with a thrown error, never a trap.
        guard pt >= 0, pt < precision else {
            throw JLIError.decodingFailed("invalid lossless point transform \(pt) for precision \(precision)")
        }
        let dcTables = prepareDCTables(scan.dcTables)
        let tables = frame.components.map { fc -> HuffmanTable in
            let sc = scan.header.components.first { $0.componentSelector == fc.id }
            return dcTables[sc?.dcTableId ?? 0] ?? StandardHuffmanTables.dcLuminance
        }

        var reader = BitReader(data: scan.entropyData)
        let half = Int32(1 << (precision - 1 - pt))   // predictor for the very first sample
        let count = w * h

        // The public greyscale destination is already the final allocation.
        // Keep prediction history in one row instead of a second full image;
        // the history stays in the point-transformed domain, before output
        // clamping, so this also preserves malformed-stream arithmetic.
        if nc == 1, let borrowed = borrowedDestination {
            if restartInterval > 0, restartInterval % w != 0 {
                throw JLIError.unsupportedJPEGFeature(
                    "lossless restart interval \(restartInterval) not a multiple of "
                    + "samples-per-row (\(w))")
            }
            // The bounded table is only useful for sufficiently large scans
            // with varied short categories. Choose the kernel once per scan.
            // Its <=32 KiB plus row history fits the existing 8-byte/sample
            // reservation at the table's >=16384-sample construction threshold.
            if predictor == 1, count >= 16384,
               tables[0].lookaheadLength[0] == 1, tables[0].lookaheadSymbol[0] == 0 {
                try ZeroRunLosslessDecoder.decode(
                    into: borrowed, width: w, height: h, half: half,
                    table: tables[0], reader: &reader, pointTransform: pt,
                    segmentRows: restartInterval > 0 ? restartInterval / w : h)
            } else if let lookup = LosslessLookahead(table: tables[0], sampleCount: count) {
                try Self.losslessGrayLookupInto(
                    borrowed, width: w, height: h, predictor: predictor, half: half,
                    table: tables[0], reader: &reader, pointTransform: pt,
                    segmentRows: restartInterval > 0 ? restartInterval / w : h, lookup: lookup)
            } else if count < 16384 {
                try Self.losslessSmallGrayInto(
                    borrowed, width: w, height: h, predictor: predictor, half: half,
                    table: tables[0], reader: &reader, pointTransform: pt,
                    segmentRows: restartInterval > 0 ? restartInterval / w : h)
            } else if predictor == 1, pt == 0, borrowed.bytesPerSample == 2 {
                if useScalarCEntropy {
                    try Self.losslessCLeftUInt16Into(
                        borrowed, width: w, height: h, half: half,
                        table: tables[0], reader: &reader,
                        segmentRows: restartInterval > 0 ? restartInterval / w : h)
                } else {
                    try Self.losslessLeftUInt16Into(
                        borrowed, width: w, height: h, half: half,
                        table: tables[0], reader: &reader,
                        segmentRows: restartInterval > 0 ? restartInterval / w : h)
                }
            } else {
                try Self.losslessGrayInto(
                    borrowed, width: w, height: h, predictor: predictor, half: half,
                    table: tables[0], reader: &reader, pointTransform: pt,
                    segmentRows: restartInterval > 0 ? restartInterval / w : h)
            }
            let format = configuration.outputPixelFormat ?? (borrowed.bytesPerSample == 1 ? .uint8 : .uint16)
            return try JLIImage(geometryOnlyWidth: w, height: h, pixelFormat: format,
                colorModel: configuration.outputColorModel ?? .grayscale,
                iccProfile: iccProfile, exif: exif)
        }

        // One flat raw buffer holds all component planes (plane c at offset
        // c·w·h): the previous nested-array form paid a retain/release plus an
        // outer-array _modify and inner-buffer uniqueness check on EVERY sample
        // — the dominant non-entropy cost of the clinical lossless path (and
        // `let p = planes[c]` aliased the buffer being written, a latent
        // full-plane-COW trap that only optimizer lifetime-shortening kept
        // benign). Uninitialized is safe: prediction reads only previously
        // written positions.
        let store = UnsafeMutableBufferPointer<Int32>.allocate(capacity: count * nc)
        defer { store.deallocate() }
        let base = store.baseAddress!

        // The scan workers are dedicated static functions (the same pattern as
        // the encoder's `trellisBlocks`): a compact hot loop is its own
        // optimization unit, so the entropy-decode chain stays within inlining
        // range, and `reader` is passed `inout` end-to-end — never captured by
        // a closure (a captured inout-mutated struct gets boxed with dynamic
        // exclusivity checks on every access).
        // Restart segmentation: row-aligned only (the constraint libjpeg-turbo
        // also enforces for lossless), so each segment's first row predicts with
        // scan-start semantics and segments are independently decodable. The
        // scan workers need no restart awareness: a worker invoked on a
        // segment's rows treats its first row as the \"first row\" (y == 0),
        // which IS the post-restart prediction state.
        var segRows = 0
        if restartInterval > 0 {
            guard restartInterval % w == 0 else {
                throw JLIError.unsupportedJPEGFeature(
                    "lossless restart interval \(restartInterval) not a multiple of "
                    + "samples-per-row (\(w))")
            }
            segRows = restartInterval / w
        }
        let numSegments = segRows > 0 ? (h + segRows - 1) / segRows : 1

        if numSegments <= 1 {
            if nc == 1 {
                try Self.losslessScanGray(base, width: w, height: h, predictor: predictor,
                                          half: half, table: tables[0], reader: &reader)
            } else {
                try Self.losslessScanRGB(base, width: w, height: h, count: count,
                                         predictor: predictor, half: half,
                                         tables: tables, reader: &reader)
            }
        } else {
            // Parallel fast path (the clinical grayscale case): locate the RST
            // markers up front (in entropy data a 0xFF is always followed by
            // 0x00 stuffing, 0xFF fill, or a real RST byte) and decode every
            // segment concurrently — each from its own reader and into its own
            // disjoint row range. Falls back to the serial segment loop when
            // the marker layout is anything but the expected one.
            var rstOffsets = [Int]()
            let ed = scan.entropyData
            // Acquire one synchronous view for the scan. In particular, do not
            // fetch NSData.bytes (and its inner-pointer lifetime machinery) for
            // every entropy byte. Only integer marker offsets leave this scope.
            try ed.withUnsafeBytes { bytes in
                var si = 0
                scanLoop: while si + 1 < bytes.count {
                    if si % 4096 == 0 { try NativeOperation.check() }
                    if bytes[si] != 0xFF { si += 1; continue }
                    switch bytes[si + 1] {
                    case 0x00: si += 2                                  // stuffed data byte
                    case 0xFF: si += 1                                  // fill byte
                    case 0xD0...0xD7: rstOffsets.append(si); si += 2    // restart marker
                    default: break scanLoop                             // foreign marker — bail
                    }
                }
            }
            let parallelOK = NativeOperation.current == nil && nc == 1 && rstOffsets.count == numSegments - 1
                && count >= JLIDecoder.losslessSegmentParallelMinSamples
            if parallelOK {
                let table = tables[0]
                // Immutable snapshots for the @Sendable workers (the vars above
                // are never mutated past this point; the lets make that a
                // compiler-checked fact).
                let segRowsFinal = segRows
                let markers = rstOffsets
                var errors = [Error?](repeating: nil, count: numSegments)
                errors.withUnsafeMutableBufferPointer { eb in
                    let slots = LosslessSegmentSlots(errors: eb.baseAddress!, plane: base)
                    DispatchQueue.concurrentPerform(iterations: numSegments) { k in
                        let startRow = k * segRowsFinal
                        let rows = min(segRowsFinal, h - startRow)
                        var segReader = k == 0
                            ? BitReader(data: ed)
                            : BitReader(data: ed, startingAt: markers[k - 1] + 2)
                        do {
                            try Self.losslessScanGray(
                                slots.plane + startRow * w, width: w, height: rows,
                                predictor: predictor, half: half, table: table,
                                reader: &segReader)
                            // Behavioral equivalence with the serial path on
                            // CORRUPT input: serial's skipRestartMarker throws
                            // unless each segment ends exactly at its marker
                            // (modulo 0xFF fill). An under-consuming corrupt
                            // segment would otherwise be silently accepted here
                            // — wrong pixels returned as success on exactly the
                            // large clinical images this path targets.
                            if k < numSegments - 1 {
                                segReader.alignToByte()
                                var pos = segReader.byteOffset
                                ed.withUnsafeBytes { bytes in
                                    while pos < markers[k], bytes[pos] == 0xFF { pos += 1 }
                                }
                                guard pos == markers[k] else {
                                    throw JLIError.decodingFailed(
                                        "lossless restart segment \(k) ended at byte "
                                        + "\(segReader.byteOffset), expected RST at \(markers[k])")
                                }
                            }
                        } catch {
                            slots.errors[k] = error
                        }
                    }
                }
                if let e = errors.compactMap({ $0 }).first { throw e }
            } else {
                for k in 0..<numSegments {
                    if k > 0 { try reader.skipRestartMarker(expectedIndex: (k - 1) & 7) }
                    let startRow = k * segRows
                    let rows = min(segRows, h - startRow)
                    if nc == 1 {
                        try Self.losslessScanGray(
                            base + startRow * w, width: w, height: rows,
                            predictor: predictor, half: half, table: tables[0],
                            reader: &reader)
                    } else {
                        try Self.losslessScanRGB(
                            base + startRow * w, width: w, height: rows, count: count,
                            predictor: predictor, half: half, tables: tables,
                            reader: &reader)
                    }
                }
            }
        }

        // Interleave planes → output. 1 component = grayscale; 3 = RGB (direct).
        // Pointer loops over an uninitialized output buffer (every byte is
        // written); the inverse point-transform shift and clamping semantics
        // are unchanged.
        let model = configuration.outputColorModel ?? (nc == 1 ? .grayscale : .rgb)
        let bps = borrowedDestination?.bytesPerSample ?? (precision <= 8 ? 1 : 2)
        let outputFormat = configuration.outputPixelFormat ?? (bps == 1 ? .uint8 : .uint16)

        // One interleave path, whichever plane the samples go to. The borrowed
        // branch honours the caller's row stride and never writes the padding
        // between the row payload and `rowBytes`, so caller sentinels survive.
        if let borrowed = borrowedDestination {
            let needed = (h - 1) * borrowed.rowBytes + w * nc * bps
            guard borrowed.bytes.count >= needed else {
                throw JLIError.bufferSizeMismatch(expected: needed, actual: borrowed.bytes.count)
            }
            try jliWriteInterleavedPlanes(
                from: base, into: borrowed.bytes, width: w, height: h,
                rowSamples: borrowed.rowBytes / bps, componentCount: nc,
                samplesPerPlane: count, bytesPerSample: bps, pointTransform: pt)
            // Geometry only: the samples are in the caller's allocation, and
            // MEM-12 says a relabelled final image is not workspace, so none
            // is produced here.
            return try JLIImage(geometryOnlyWidth: w, height: h, pixelFormat: outputFormat,
                                colorModel: model, iccProfile: iccProfile, exif: exif)
        }

        var bytes = [UInt8](unsafeUninitializedCapacity: count * nc * bps) { _, n in
            n = count * nc * bps
        }
        try bytes.withUnsafeMutableBufferPointer { bp in
            try jliWriteInterleavedPlanes(
                from: base, into: UnsafeMutableRawBufferPointer(bp), width: w, height: h,
                rowSamples: w * nc, componentCount: nc, samplesPerPlane: count,
                bytesPerSample: bps, pointTransform: pt)
        }
        return try JLIImage(width: w, height: h, pixelFormat: outputFormat,
                            colorModel: model, data: bytes,
                            iccProfile: iccProfile, exif: exif)
    }

    /// Minimum block count before Step-7 reconstruction fans out across cores;
    /// below a few thousand blocks the dispatch overhead wins. Lock-protected
    /// because the serial/parallel equality tests mutate it while other tests
    /// may decode concurrently — both gate values are behaviorally equivalent
    /// (that's what the tests prove), but the access must not be a data race.
    /// No production code mutates it.
    static var reconstructMinBlocksPerChunk: Int {
        get { gateLock.lock(); defer { gateLock.unlock() }; return _reconstructMinBlocksPerChunk }
        set { gateLock.lock(); defer { gateLock.unlock() }; _reconstructMinBlocksPerChunk = newValue }
    }

    /// Minimum pixel count before a restart-segmented lossless scan decodes its
    /// segments concurrently. Same locking rationale as
    /// ``reconstructMinBlocksPerChunk``.
    static var losslessSegmentParallelMinSamples: Int {
        get { gateLock.lock(); defer { gateLock.unlock() }; return _losslessSegmentParallelMinSamples }
        set { gateLock.lock(); defer { gateLock.unlock() }; _losslessSegmentParallelMinSamples = newValue }
    }
    private static let gateLock = NSLock()
    nonisolated(unsafe) private static var _reconstructMinBlocksPerChunk = 2048
    nonisolated(unsafe) private static var _losslessSegmentParallelMinSamples = 1 << 16

    /// `@unchecked Sendable` carrier for segment-parallel lossless decode:
    /// worker `k` writes only its segment's disjoint row range of `plane` and
    /// its own `errors` slot.
    private struct LosslessSegmentSlots: @unchecked Sendable {
        let errors: UnsafeMutablePointer<Error?>
        let plane: UnsafeMutablePointer<Int32>
    }

    /// `@unchecked Sendable` carrier for parallel Step-7 reconstruction: each
    /// worker reads shared `zz`/`qt` and writes only its own bounded scratch
    /// slot plus the disjoint plane tiles of its assigned blocks. A slot is
    /// reused only by that worker after its preceding synchronous batch ends.
    /// NativeOperation.perform joins every worker before these borrows end.
    private struct ReconstructPtrs: @unchecked Sendable {
        let zz: UnsafePointer<Int32>
        let qt: UnsafePointer<Float>
        let px: UnsafeMutablePointer<Float>
        let scratch: UnsafeMutablePointer<Float>
        let plane: UnsafeMutablePointer<Float>
    }

    /// Reconstructs `blocks` of one component: fused dequant+IDCT (bit-identical
    /// to the separate passes — same convert and multiply per element), level
    /// shift + clamp, then a per-row memcpy scatter of each block's in-bounds
    /// region into the component-sized plane. Callable on any disjoint block
    /// range; block tiles never overlap, so partitioning is race-free.
    private static func reconstructBlocks(
        _ blocks: Range<Int>, ptrs: ReconstructPtrs, blocksH: Int,
        compWidth: Int, compHeight: Int, precision: Int, scratchOffset: Int
    ) {
        let m = blocks.count
        guard m > 0 else { return }
        let base = blocks.lowerBound
        let px = ptrs.px + scratchOffset
        AccelerateDSP.inverseDCTBatchDequantized(
            zigzag: ptrs.zz + base * 64, quantTable: ptrs.qt,
            output: px, scratch: ptrs.scratch + scratchOffset, blockCount: m)

        // Level shift +2^(P-1) + clamp [0, 2^P-1] — 128/255 for 8-bit,
        // 2048/4095 for 12-bit; per-element ops, so chunking changes nothing.
        var center = Float(1 << (precision - 1))
        var lo: Float = 0.0, hi = Float((1 << precision) - 1)
        let n = JLI_DSPCount(m * 64)
        jliDSP_vsadd(px, 1, &center, px, 1, n)
        jliDSP_vclip(px, 1, &lo, &hi, px, 1, n)

        for bi in 0..<m {
            let b = base + bi
            let startX = (b % blocksH) * 8
            let startY = (b / blocksH) * 8
            // MCU geometry can pad subsampled components past the component's
            // actual extent (e.g. a 4:2:0 luma grid rounded up to even blocks on
            // a tiny image) — such blocks decode but land entirely outside the
            // exact-size plane and must be skipped, never clamped negative.
            guard startX < compWidth, startY < compHeight else { continue }
            let blockBase = bi * 64
            let runW = min(8, compWidth - startX)
            for y in 0..<8 {
                let py = startY + y
                if py >= compHeight { break }
                memcpy(ptrs.plane + py * compWidth + startX,
                       px + blockBase + y * 8,
                       runW * MemoryLayout<Float>.size)
            }
        }
    }

    /// Serial bounded reconstruction into caller storage. The component plane
    /// writer and this path share the same sample conversion, and the IDCT,
    /// level shift and clipping keep exactly the existing 1024-block grouping.
    /// No pointer escapes these nested borrows or crosses a worker boundary.
    private static func reconstructGreyscaleInto(
        _ zigzag: [Int32], quantTable: [Float], blocksPerRow: Int,
        width: Int, height: Int, precision: Int, floatOutput: Bool,
        destination: BorrowedSampleDestination
    ) throws {
        try validateGreyscaleDestination(destination, width: width, height: height,
                                         precision: precision, floatOutput: floatOutput)
        let blockCount = zigzag.count / 64
        let scratchCount = min(1024, blockCount) * 64
        var pixels = [Float](unsafeUninitializedCapacity: scratchCount) { _, count in count = scratchCount }
        var scratch = [Float](unsafeUninitializedCapacity: scratchCount) { _, count in count = scratchCount }
        try zigzag.withUnsafeBufferPointer { zz in
            try quantTable.withUnsafeBufferPointer { qt in
                try pixels.withUnsafeMutableBufferPointer { px in
                    try scratch.withUnsafeMutableBufferPointer { sc in
                        for first in stride(from: 0, to: blockCount, by: 1024) {
                            try NativeOperation.check()
                            let count = min(1024, blockCount - first)
                            try reconstructGreyscaleBatch(
                                coefficients: zz.baseAddress! + first * 64, quantTable: qt.baseAddress!,
                                pixels: px.baseAddress!, scratch: sc.baseAddress!, firstBlock: first,
                                blockCount: count, blocksPerRow: blocksPerRow,
                                width: width, height: height, precision: precision,
                                floatOutput: floatOutput, destination: destination)
                        }
                    }
                }
            }
        }
    }

    /// Sequential greyscale retains one coefficient/output batch and one Float
    /// scratch batch. Packing consumes every Int32 coefficient before that
    /// storage is temporarily rebound for Float output. Both borrows and the
    /// final destination stay on this thread; no Int32 access occurs while
    /// rebound, and the binding is restored on normal and throwing returns.
    private static func decodeSequentialGreyscaleInto(
        reader: inout BitReader, dcTable: HuffmanTable, acTable: HuffmanTable, lookup: ACLookahead?,
        quantTable: [Float], plan: SequentialGreyscalePlan,
        width: Int, height: Int, precision: Int, restartInterval: Int,
        floatOutput: Bool, destination: BorrowedSampleDestination
    ) throws {
        try validateGreyscaleDestination(destination, width: width, height: height,
                                         precision: precision, floatOutput: floatOutput)
        if plan.pipelined && NativeOperation.workerLimit > 1 {
            try PipelinedGreyscaleDecoder.decode(reader: &reader,
                dcTable: dcTable, acTable: acTable, lookup: lookup, quantTable: quantTable,
                plan: plan, width: width, height: height, precision: precision,
                restartInterval: restartInterval, floatOutput: floatOutput, destination: destination)
            return
        }
        if plan.parallelLanes > 1 {
            try ParallelSequentialGreyscaleDecoder.decode(reader: &reader,
                dcTable: dcTable, acTable: acTable, lookup: lookup, quantTable: quantTable,
                plan: plan, width: width, height: height, precision: precision,
                restartInterval: restartInterval, floatOutput: floatOutput, destination: destination)
            return
        }
        let scratchCount = plan.batchBlocks * 64
        var scratch = [Float](unsafeUninitializedCapacity: scratchCount) { _, count in count = scratchCount }
        try quantTable.withUnsafeBufferPointer { qt in
            try scratch.withUnsafeMutableBufferPointer { sc in
                try SequentialGreyscaleDecoder.decodeBatches(reader: &reader,
                    dcTable: dcTable, acTable: acTable, lookup: lookup,
                    blocksPerRow: plan.blocksPerRow, blockRows: plan.blockRows,
                    precision: precision, restartInterval: restartInterval) { coefficients, first in
                    let sampleCount = coefficients.count, blockCount = sampleCount / 64
                    let base = coefficients.baseAddress!
                    let dcOnly = AccelerateDSP.prepareDCOnlyDCTBatch(zigzag: UnsafePointer(base),
                        quantTable: qt.baseAddress!, scratch: sc.baseAddress!, blockCount: blockCount)
                    if dcOnly {
                        var center = Float(1 << (precision - 1))
                        var low: Float = 0, high = Float((1 << precision) - 1)
                        jliDSP_vsadd(sc.baseAddress!, 1, &center, sc.baseAddress!, 1, blockCount)
                        jliDSP_vclip(sc.baseAddress!, 1, &low, &high, sc.baseAddress!, 1, blockCount)
                        try SharedDCTStorage.writeGreyscaleConstantBlocks(
                            UnsafeBufferPointer(start: sc.baseAddress!, count: blockCount),
                            firstBlock: first, blocksPerRow: plan.blocksPerRow,
                            width: width, height: height, precision: precision,
                            floatOutput: floatOutput, into: destination)
                        return
                    }
                    AccelerateDSP.packDequantizedDCTBatch(zigzag: UnsafePointer(base),
                        quantTable: qt.baseAddress!, scratch: sc.baseAddress!, blockCount: blockCount)
                    // Plan admission proves matching stride/alignment. Packing
                    // has finished all coefficient reads before changing binding.
                    try base.withMemoryRebound(to: Float.self, capacity: sampleCount) { pixels in
                        AccelerateDSP.inverseDCTBatchPacked(output: pixels, scratch: sc.baseAddress!,
                            blockCount: blockCount)
                        try writeReconstructedGreyscaleBatch(pixels: pixels, firstBlock: first,
                            blockCount: blockCount, blocksPerRow: plan.blocksPerRow,
                            width: width, height: height, precision: precision,
                            floatOutput: floatOutput, destination: destination)
                    }
                }
            }
        }
    }

    private static func reconstructGreyscaleBatch(
        coefficients: UnsafePointer<Int32>, quantTable: UnsafePointer<Float>,
        pixels: UnsafeMutablePointer<Float>, scratch: UnsafeMutablePointer<Float>,
        firstBlock: Int, blockCount: Int, blocksPerRow: Int,
        width: Int, height: Int, precision: Int, floatOutput: Bool,
        destination: BorrowedSampleDestination
    ) throws {
        AccelerateDSP.inverseDCTBatchDequantized(zigzag: coefficients, quantTable: quantTable,
            output: pixels, scratch: scratch, blockCount: blockCount)
        try writeReconstructedGreyscaleBatch(pixels: pixels, firstBlock: firstBlock,
            blockCount: blockCount, blocksPerRow: blocksPerRow,
            width: width, height: height, precision: precision,
            floatOutput: floatOutput, destination: destination)
    }

    private static func writeReconstructedGreyscaleBatch(
        pixels: UnsafeMutablePointer<Float>, firstBlock: Int, blockCount: Int, blocksPerRow: Int,
        width: Int, height: Int, precision: Int, floatOutput: Bool,
        destination: BorrowedSampleDestination
    ) throws {
        var center = Float(1 << (precision - 1))
        var lo: Float = 0, hi = Float((1 << precision) - 1)
        let samples = JLI_DSPCount(blockCount * 64)
        jliDSP_vsadd(pixels, 1, &center, pixels, 1, samples)
        jliDSP_vclip(pixels, 1, &lo, &hi, pixels, 1, samples)
        try SharedDCTStorage.writeGreyscaleBlocks(
            UnsafeBufferPointer(start: pixels, count: blockCount * 64),
            firstBlock: firstBlock, blocksPerRow: blocksPerRow,
            width: width, height: height, precision: precision,
            floatOutput: floatOutput, into: destination)
    }

    private static func validateGreyscaleDestination(
        _ destination: BorrowedSampleDestination, width: Int, height: Int,
        precision: Int, floatOutput: Bool
    ) throws {
        let bps = destination.bytesPerSample
        guard floatOutput ? bps == 4 : (bps == 1 && precision <= 8) || bps == 2 else {
            throw JLIError.unsupportedJPEGFeature("Invalid greyscale destination")
        }
        let rowPayload = try checkedMultiply(width, bps)
        guard destination.rowBytes >= rowPayload else {
            throw JLIError.decodingFailed("invalid greyscale destination layout")
        }
        let needed = try checkedAdd(checkedMultiply(height - 1, destination.rowBytes), rowPayload)
        guard destination.bytes.count >= needed else {
            throw JLIError.bufferSizeMismatch(expected: needed, actual: destination.bytes.count)
        }
    }

    /// The untransformed left predictor needs only the previous row's first
    /// sample. Every reconstructed value is already reduced modulo 65536, so
    /// its UInt16 representation needs neither a shift nor output clamping.
    /// The checked destination borrow remains synchronous, including odd bases
    /// and strides; the raw word store has no alignment requirement.
    @inline(never)
    private static func losslessLeftUInt16Into(
        _ destination: BorrowedSampleDestination, width w: Int, height h: Int,
        half: Int32, table: HuffmanTable, reader: inout BitReader, segmentRows: Int
    ) throws {
        guard (1...65535).contains(w), (1...65535).contains(h), segmentRows > 0,
              destination.bytesPerSample == 2, destination.rowBytes >= w * 2 else {
            throw JLIError.decodingFailed("invalid lossless destination layout")
        }
        let (rowOffset, overflow1) = (h - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (needed, overflow2) = rowOffset.addingReportingOverflow(w * 2)
        guard !overflow1, !overflow2, needed <= destination.bytes.count,
              let output = destination.bytes.baseAddress else {
            throw JLIError.decodingFailed("lossless destination is too small")
        }
        var previousRowFirst = half
        for y in 0..<h {
            try NativeOperation.check()
            let segmentY = y % segmentRows
            if y > 0, segmentY == 0 {
                try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
            }
            let outputRow = output + y * destination.rowBytes
            let prediction = segmentY == 0 ? half : previousRowFirst
            var value = (prediction + (try losslessDifference(table, &reader))) & 0xFFFF
            previousRowFirst = value
            outputRow.storeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian, as: UInt16.self)
            for x in 1..<w {
                value = (value + (try losslessDifference(table, &reader))) & 0xFFFF
                outputRow.storeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian,
                    toByteOffset: x * 2, as: UInt16.self)
            }
        }
    }

    /// Optional large-scan row leaf. Cancellation and restart handling stay on
    /// the caller at exactly the same row boundaries as the Swift reference.
    /// No row can exceed the validated JPEG width of 65,535 samples. Metadata
    /// is prepared once per scan; the provider borrow is never used by workers.
    @inline(never)
    private static func losslessCLeftUInt16Into(
        _ destination: BorrowedSampleDestination, width w: Int, height h: Int,
        half: Int32, table: HuffmanTable, reader: inout BitReader, segmentRows: Int
    ) throws {
        guard (1...65535).contains(w), (1...65535).contains(h), segmentRows > 0,
              destination.bytesPerSample == 2, destination.rowBytes >= w * 2 else {
            throw JLIError.decodingFailed("invalid lossless destination layout")
        }
        let (rowOffset, overflow1) = (h - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (needed, overflow2) = rowOffset.addingReportingOverflow(w * 2)
        guard !overflow1, !overflow2, needed <= destination.bytes.count,
              let output = destination.bytes.baseAddress else {
            throw JLIError.decodingFailed("lossless destination is too small")
        }
        try CLosslessRowKernel.withBorrowed(table: table, enabled: true) { kernel in
            guard let kernel else {
                try losslessLeftUInt16Into(destination, width: w, height: h, half: half,
                    table: table, reader: &reader, segmentRows: segmentRows)
                return
            }
            var previousRowFirst = half
            for y in 0..<h {
                try NativeOperation.check()
                let segmentY = y % segmentRows
                if y > 0, segmentY == 0 {
                    try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
                }
                let row = UnsafeMutableRawBufferPointer(
                    start: output + y * destination.rowBytes, count: w * 2)
                let decoded = try reader.decodeLeftUInt16Row(using: kernel, sampleCount: w,
                    seed: segmentY == 0 ? half : previousRowFirst, into: row)
                previousRowFirst = decoded.first
            }
        }
    }

    /// Synchronous borrowed-output scan. Only one row of predictor history is
    /// live; `aboveLeft` saves the previous-row sample before its slot is reused.
    /// Every slot is written on the first row of a restart segment before any
    /// subsequent row reads it. Neither pointer escapes this call.
    private static func losslessGrayInto(
        _ destination: BorrowedSampleDestination, width w: Int, height h: Int,
        predictor: Int, half: Int32, table: HuffmanTable, reader: inout BitReader,
        pointTransform pt: Int, segmentRows: Int
    ) throws {
        // Dispatch validates these frame bounds. Restating them in this
        // kernel preserves safe shift/index ranges if the optimiser outlines
        // it instead of specialising it at the validated call site.
        guard (1...65535).contains(w), (1...65535).contains(h), (0...15).contains(pt) else {
            throw JLIError.decodingFailed("Invalid lossless frame or point transform")
        }
        let bps = destination.bytesPerSample
        guard bps == 1 || bps == 2, destination.rowBytes >= w * bps else {
            throw JLIError.decodingFailed("invalid lossless destination layout")
        }
        let (rowOffset, overflow1) = (h - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (needed, overflow2) = rowOffset.addingReportingOverflow(w * bps)
        guard !overflow1, !overflow2, needed <= destination.bytes.count,
              let output = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw JLIError.decodingFailed("lossless destination is too small")
        }
        let history = UnsafeMutableBufferPointer<Int32>.allocate(capacity: w)
        defer { history.deallocate() }
        // w >= 1 has already been validated by decodeLossless.
        guard let row = history.baseAddress else { return }
        for y in 0..<h {
            try NativeOperation.check()
            let segmentY = y % segmentRows
            if y > 0, segmentY == 0 {
                try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
            }
            let outputRow = output + y * destination.rowBytes
            if predictor == 1 {
                // The left predictor only needs the preceding row's first
                // sample. Avoid all other history loads/stores in this common
                // scan mode, while retaining the identical entropy reader.
                var value = segmentY == 0 ? half : row[0]
                for x in 0..<w {
                    value = (value + (try losslessDifference(table, &reader))) & 0xFFFF
                    if x == 0 { row[0] = value }
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            } else {
                var left = half, aboveLeft: Int32 = 0
                for x in 0..<w {
                    let above = segmentY == 0 ? half : row[x]
                    let predicted: Int32
                    if x == 0 { predicted = above }
                    else if segmentY == 0 { predicted = left }
                    else {
                        switch predictor {
                        case 2: predicted = above
                        case 3: predicted = aboveLeft
                        case 4: predicted = left + above - aboveLeft
                        case 5: predicted = left + ((above - aboveLeft) >> 1)
                        case 6: predicted = above + ((left - aboveLeft) >> 1)
                        default: predicted = (left + above) >> 1
                        }
                    }
                    let value = (predicted + (try losslessDifference(table, &reader))) & 0xFFFF
                    row[x] = value
                    left = value
                    aboveLeft = above
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            }
        }
    }

    // Keep the large scalar kernel's compiled shape independent of the extra
    // polling state. This path is limited to fewer than 16384 total samples;
    // both kernels use the same predictor, entropy and output arithmetic.
    @inline(never)
    private static func losslessSmallGrayInto(
        _ destination: BorrowedSampleDestination, width w: Int, height h: Int,
        predictor: Int, half: Int32, table: HuffmanTable, reader: inout BitReader,
        pointTransform pt: Int, segmentRows: Int
    ) throws {
        let bps = destination.bytesPerSample
        guard bps == 1 || bps == 2, destination.rowBytes >= w * bps else {
            throw JLIError.decodingFailed("invalid lossless destination layout")
        }
        let (rowOffset, overflow1) = (h - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (needed, overflow2) = rowOffset.addingReportingOverflow(w * bps)
        guard !overflow1, !overflow2, needed <= destination.bytes.count,
              let output = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw JLIError.decodingFailed("lossless destination is too small")
        }
        let history = UnsafeMutableBufferPointer<Int32>.allocate(capacity: w)
        defer { history.deallocate() }
        // w >= 1 has already been validated by decodeLossless.
        guard let row = history.baseAddress else { return }
        // Narrow rows share a bounded polling unit of at most 1024 samples.
        // Wider rows retain their existing per-row boundary. Publication still
        // checks cancellation/deadline after this synchronous kernel returns.
        let rowsPerCheck = max(1, 1024 / w)
        var rowsUntilCheck = 0
        for y in 0..<h {
            if rowsUntilCheck == 0 {
                try NativeOperation.check()
                rowsUntilCheck = rowsPerCheck
            }
            rowsUntilCheck -= 1
            let segmentY = y % segmentRows
            if y > 0, segmentY == 0 {
                try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
            }
            let outputRow = output + y * destination.rowBytes
            if predictor == 1 {
                // The left predictor only needs the preceding row's first
                // sample. Avoid all other history loads/stores in this common
                // scan mode, while retaining the identical entropy reader.
                var value = segmentY == 0 ? half : row[0]
                for x in 0..<w {
                    value = (value + (try losslessDifference(table, &reader))) & 0xFFFF
                    if x == 0 { row[0] = value }
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            } else {
                var left = half, aboveLeft: Int32 = 0
                for x in 0..<w {
                    let above = segmentY == 0 ? half : row[x]
                    let predicted: Int32
                    if x == 0 { predicted = above }
                    else if segmentY == 0 { predicted = left }
                    else {
                        switch predictor {
                        case 2: predicted = above
                        case 3: predicted = aboveLeft
                        case 4: predicted = left + above - aboveLeft
                        case 5: predicted = left + ((above - aboveLeft) >> 1)
                        case 6: predicted = above + ((left - aboveLeft) >> 1)
                        default: predicted = (left + above) >> 1
                        }
                    }
                    let value = (predicted + (try losslessDifference(table, &reader))) & 0xFFFF
                    row[x] = value
                    left = value
                    aboveLeft = above
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            }
        }
    }

    @inline(__always)
    private static func losslessDifference(_ table: HuffmanTable, _ reader: inout BitReader) throws -> Int32 {
        if let difference = reader.fastDecodeLosslessDifference(table) { return difference }
        let category = Int(try HuffmanDecoder.decodeSymbol(from: &reader, table: table))
        if category == 0 { return 0 }
        if category == 16 { return -32768 }
        return try HuffmanDecoder.decodeValue(from: &reader, category: category)
    }

    @inline(__always)
    private static func writeLosslessSample(
        _ value: Int32, _ output: UnsafeMutablePointer<UInt8>, _ x: Int, _ bps: Int, _ pt: Int
    ) {
        if bps == 1 {
            output[x] = UInt8(clamping: Int(value) << pt)
        } else {
            let shifted = UInt16(clamping: Int(value) << pt)
            // The raw store supports odd addresses, as in the zero-run kernel.
            // The destination preflight covers both sample bytes of every pixel.
            UnsafeMutableRawPointer(output).storeBytes(
                of: shifted.littleEndian, toByteOffset: x * 2, as: UInt16.self)
        }
    }

    // This separate kernel preserves the original scalar loop's compiled
    // shape. Its prediction/output arithmetic intentionally matches the scalar
    // kernel above; the large predictor/restart/padding matrix checks both.
    /// Synchronous borrowed-output scan. Only one row of predictor history is
    /// live; `aboveLeft` saves the previous-row sample before its slot is reused.
    /// Every slot is written on the first row of a restart segment before any
    /// subsequent row reads it. Neither pointer escapes this call.
    // Keep this boundary: measured release builds otherwise lose scalar
    // caller specialisation and regress scans that do not use the lookup.
    @inline(never)
    private static func losslessGrayLookupInto(
        _ destination: BorrowedSampleDestination, width w: Int, height h: Int,
        predictor: Int, half: Int32, table: HuffmanTable, reader: inout BitReader,
        pointTransform pt: Int, segmentRows: Int, lookup: LosslessLookahead
    ) throws {
        let bps = destination.bytesPerSample
        guard bps == 1 || bps == 2, destination.rowBytes >= w * bps else {
            throw JLIError.decodingFailed("invalid lossless destination layout")
        }
        let (rowOffset, overflow1) = (h - 1).multipliedReportingOverflow(by: destination.rowBytes)
        let (needed, overflow2) = rowOffset.addingReportingOverflow(w * bps)
        guard !overflow1, !overflow2, needed <= destination.bytes.count,
              let output = destination.bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw JLIError.decodingFailed("lossless destination is too small")
        }
        let history = UnsafeMutableBufferPointer<Int32>.allocate(capacity: w)
        defer { history.deallocate() }
        // w >= 1 has already been validated by decodeLossless.
        guard let row = history.baseAddress else { return }
        for y in 0..<h {
            try NativeOperation.check()
            let segmentY = y % segmentRows
            if y > 0, segmentY == 0 {
                try reader.skipRestartMarker(expectedIndex: (y / segmentRows - 1) & 7)
            }
            let outputRow = output + y * destination.rowBytes
            if predictor == 1 {
                // The left predictor only needs the preceding row's first
                // sample. Avoid all other history loads/stores in this common
                // scan mode, while retaining the identical entropy reader.
                var value = segmentY == 0 ? half : row[0]
                for x in 0..<w {
                    let difference: Int32
                    if let decoded = reader.fastDecodeLosslessDifference(lookup) { difference = decoded }
                    else { difference = try losslessDifference(table, &reader) }
                    value = (value + difference) & 0xFFFF
                    if x == 0 { row[0] = value }
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            } else {
                var left = half, aboveLeft: Int32 = 0
                for x in 0..<w {
                    let above = segmentY == 0 ? half : row[x]
                    let predicted: Int32
                    if x == 0 { predicted = above }
                    else if segmentY == 0 { predicted = left }
                    else {
                        switch predictor {
                        case 2: predicted = above
                        case 3: predicted = aboveLeft
                        case 4: predicted = left + above - aboveLeft
                        case 5: predicted = left + ((above - aboveLeft) >> 1)
                        case 6: predicted = above + ((left - aboveLeft) >> 1)
                        default: predicted = (left + above) >> 1
                        }
                    }
                    let difference: Int32
                    if let decoded = reader.fastDecodeLosslessDifference(lookup) { difference = decoded }
                    else { difference = try losslessDifference(table, &reader) }
                    let value = (predicted + difference) & 0xFFFF
                    row[x] = value
                    left = value
                    aboveLeft = above
                    writeLosslessSample(value, outputRow, x, bps, pt)
                }
            }
        }
    }

    /// Grayscale (single-component) lossless scan — the clinical hot loop.
    /// Straight-line per-sample body: predict (edge cases first, then the
    /// fixed-per-scan selector switch, which the branch predictor learns),
    /// Huffman category + magnitude bits, accumulate modulo 2^16 (T.81) in the
    /// point-transformed domain, write through the raw plane pointer.
    private static func losslessScanGray(
        _ p: UnsafeMutablePointer<Int32>, width w: Int, height h: Int,
        predictor: Int, half: Int32, table: HuffmanTable, reader: inout BitReader
    ) throws {
        for y in 0..<h {
            try NativeOperation.check()
            let row = y * w, prevRow = row - w
            for x in 0..<w {
                let px: Int32
                if x == 0 {
                    px = y == 0 ? half : p[prevRow]                    // Rb (or initial)
                } else if y == 0 {
                    px = p[row + x - 1]                                // Ra
                } else {
                    let ra = p[row + x - 1], rb = p[prevRow + x], rc = p[prevRow + x - 1]
                    switch predictor {
                    case 1: px = ra
                    case 2: px = rb
                    case 3: px = rc
                    case 4: px = ra + rb - rc
                    case 5: px = ra + ((rb - rc) >> 1)
                    case 6: px = rb + ((ra - rc) >> 1)
                    default: px = (ra + rb) >> 1                       // 7
                    }
                }
                let cat = Int(try HuffmanDecoder.decodeSymbol(from: &reader, table: table))
                let diff: Int32
                if cat == 0 { diff = 0 }
                else if cat == 16 { diff = -32768 }                    // T.81 special case
                else { diff = try HuffmanDecoder.decodeValue(from: &reader, category: cat) }
                p[row + x] = (px + diff) & 0xFFFF
            }
        }
    }

    /// One interleaved-component lossless sample: predict, decode, accumulate.
    /// Static (capture-free) so the three per-pixel calls in the RGB scan carry
    /// no closure context.
    @inline(__always)
    private static func losslessSample(
        _ p: UnsafeMutablePointer<Int32>, _ t: HuffmanTable,
        _ x: Int, _ y: Int, _ row: Int, _ prevRow: Int,
        _ predictor: Int, _ half: Int32, _ reader: inout BitReader
    ) throws {
        let px: Int32
        if x == 0 {
            px = y == 0 ? half : p[prevRow]
        } else if y == 0 {
            px = p[row + x - 1]
        } else {
            let ra = p[row + x - 1], rb = p[prevRow + x], rc = p[prevRow + x - 1]
            switch predictor {
            case 1: px = ra
            case 2: px = rb
            case 3: px = rc
            case 4: px = ra + rb - rc
            case 5: px = ra + ((rb - rc) >> 1)
            case 6: px = rb + ((ra - rc) >> 1)
            default: px = (ra + rb) >> 1
            }
        }
        let cat = Int(try HuffmanDecoder.decodeSymbol(from: &reader, table: t))
        let diff: Int32
        if cat == 0 { diff = 0 }
        else if cat == 16 { diff = -32768 }
        else { diff = try HuffmanDecoder.decodeValue(from: &reader, category: cat) }
        p[row + x] = (px + diff) & 0xFFFF
    }

    /// Three-component (RGB) lossless scan: components interleaved per sample
    /// (1×1 sampling), each with its own plane pointer and Huffman table.
    private static func losslessScanRGB(
        _ base: UnsafeMutablePointer<Int32>, width w: Int, height h: Int, count: Int,
        predictor: Int, half: Int32, tables: [HuffmanTable], reader: inout BitReader
    ) throws {
        let t0 = tables[0], t1 = tables[1], t2 = tables[2]
        let p0 = base, p1 = base + count, p2 = base + 2 * count
        for y in 0..<h {
            try NativeOperation.check()
            let row = y * w, prevRow = row - w
            for x in 0..<w {
                try losslessSample(p0, t0, x, y, row, prevRow, predictor, half, &reader)
                try losslessSample(p1, t1, x, y, row, prevRow, predictor, half, &reader)
                try losslessSample(p2, t2, x, y, row, prevRow, predictor, half, &reader)
            }
        }
    }

    // MARK: - Private Helpers

    /// Separable contraction matrix `A` (size `bs × 8`, `bs = 8/scale`, row-major)
    /// that turns an 8×8 block of dequantized DCT coefficients `F` into its
    /// `bs × bs` box-averaged tile via `out = A · F · Aᵀ`. Row `I` averages the
    /// 8-point inverse-DCT basis over the `scale` source positions of output `I`:
    /// `A[I,u] = ½·C(u)·(1/scale)·Σ_{x∈box_I} cos((2x+1)uπ/16)`, `C(0)=1/√2`.
    /// This is an exact (not approximate) mean of the full-IDCT output over each
    /// `scale × scale` box, matching the DC-only `scale == 8` case when `bs == 1`.
    private static func boxAverageMatrix(scale: Int) -> [Float] {
        let bs = 8 / scale
        var a = [Float](repeating: 0, count: bs * 8)
        for capI in 0..<bs {
            for u in 0..<8 {
                let cu = u == 0 ? (1.0 / 2.0.squareRoot()) : 1.0
                var s = 0.0
                for x in (capI * scale)..<(capI * scale + scale) {
                    s += cos((Double(2 * x + 1) * Double(u) * Double.pi) / 16.0)
                }
                a[capI * 8 + u] = Float(0.5 * cu * (s / Double(scale)))
            }
        }
        return a
    }

    /// DC Huffman tables keyed by table id, with standard tables filled in for
    /// ids 0/1. Keyed (not positional) so a scan referencing any 4-bit table id
    /// (0–15) resolves with a fallback instead of indexing past a fixed array.
    private func prepareDCTables(_ parsed: [Int: HuffmanTable]) -> [Int: HuffmanTable] {
        var tables = parsed
        if tables[0] == nil { tables[0] = StandardHuffmanTables.dcLuminance }
        if tables[1] == nil { tables[1] = StandardHuffmanTables.dcChrominance }
        return tables
    }

    /// Serializes a sample plane (already interleaved if multi-component) to a
    /// 32-bit **little-endian** float byte buffer for `.float32` output — the raw
    /// reconstructed sample values, with no rounding or normalization.
    static func floatsToLE(_ values: [Float]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: values.count * 4)
        out.withUnsafeMutableBytes { dst in
            for (i, v) in values.enumerated() {
                let bits = v.bitPattern   // IEEE-754; store little-endian
                dst[i * 4]     = UInt8(bits & 0xFF)
                dst[i * 4 + 1] = UInt8((bits >> 8) & 0xFF)
                dst[i * 4 + 2] = UInt8((bits >> 16) & 0xFF)
                dst[i * 4 + 3] = UInt8((bits >> 24) & 0xFF)
            }
        }
        return out
    }

    /// AC Huffman tables keyed by table id, with standard tables filled in for
    /// ids 0/1. See ``prepareDCTables(_:)``.
    private func prepareACTables(_ parsed: [Int: HuffmanTable]) -> [Int: HuffmanTable] {
        var tables = parsed
        if tables[0] == nil { tables[0] = StandardHuffmanTables.acLuminance }
        if tables[1] == nil { tables[1] = StandardHuffmanTables.acChrominance }
        return tables
    }

    /// Absolute upper bound on the number of samples (width × height) the decoder
    /// will allocate planes for, regardless of the per-dimension 65535 cap. This is
    /// a decompression-bomb / denial-of-service guard: a tiny crafted header must
    /// not be able to force a multi-gigabyte allocation (an uncatchable OOM trap).
    /// 268,435,456 (2^28 ≈ 268 MP) comfortably exceeds any diagnostic radiology
    /// image (mammography ~24 MP, large DX ~16 MP) while blocking the 4.29e9-pixel
    /// worst case the SOF fields would otherwise permit.
    static let maxDecodablePixels = 1 << 28

    /// Rejects structurally-invalid frames that the decode pipeline cannot
    /// handle without trapping — malformed input (e.g. JPEG-in-DICOM from an
    /// untrusted source) must fail with a thrown ``JLIError``, never a crash.
    private func validateDecodable(_ frame: JPEGFrameInfo, quantTableCount: Int) throws {
        // Precision drives the level shift `1 << (precision-1)`, which traps for
        // precision 0; we only decode 8-bit (color/gray) and 12-bit (gray).
        guard frame.precision == 8 || frame.precision == 12 else {
            throw JLIError.unsupportedJPEGFeature(
                "sample precision \(frame.precision) (only 8 and 12 supported)")
        }
        // Dimensions: positive and within the 16-bit SOF field range. Zero width
        // or height would divide by zero when computing the MCU grid.
        guard frame.width >= 1, frame.height >= 1,
              frame.width <= 65535, frame.height <= 65535 else {
            throw JLIError.decodingFailed("invalid image dimensions \(frame.width)×\(frame.height)")
        }
        // Decompression-bomb guard: the 16-bit SOF fields permit up to ~4.29e9
        // pixels, whose coefficient/scratch planes would OOM-trap from a ~20-byte
        // header. Reject anything beyond `maxDecodablePixels` before allocating.
        guard frame.width * frame.height <= JLIDecoder.maxDecodablePixels else {
            throw JLIError.decodingFailed(
                "image too large: \(frame.width)×\(frame.height) exceeds \(JLIDecoder.maxDecodablePixels)-pixel limit")
        }
        // Only grayscale (1) and YCbCr (3) layouts are decodable; the color path
        // assumes exactly three planes (Y, Cb, Cr).
        guard frame.components.count == 1 || frame.components.count == 3 else {
            throw JLIError.unsupportedJPEGFeature(
                "\(frame.components.count)-component JPEG (only 1 or 3 supported)")
        }
        for comp in frame.components {
            // Sampling factors are 1–4 per T.81; a zero factor zeroes the max and
            // divides by zero in the MCU-grid math.
            guard (1...4).contains(comp.horizontalSampling),
                  (1...4).contains(comp.verticalSampling) else {
                throw JLIError.decodingFailed("invalid sampling factor for component \(comp.id)")
            }
            // The component must reference a quant table that was actually defined.
            guard comp.quantTableIndex >= 0, comp.quantTableIndex < quantTableCount else {
                throw JLIError.decodingFailed(
                    "component \(comp.id) references undefined quant table \(comp.quantTableIndex)")
            }
        }
    }
}


// MARK: - Shared-storage entry for the contract surface

extension JLIDecoder {
    /// Decode a lossless greyscale JPEG writing final samples into `plane`.
    /// Synchronous throughout, so the borrow cannot outlive the caller's
    /// storage lease.
    func decodeLosslessGreyscale(
        from data: [UInt8], into plane: BorrowedSampleDestination,
        configuration: JLIDecoderConfiguration
    ) throws -> JLIImage {
        guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
            throw JLIError.invalidJPEGData
        }
        var markerReader = MarkerReader(data: data)
        let parsed = try markerReader.parse()
        let frame = parsed.frameInfo
        guard !parsed.scans.isEmpty else {
            throw JLIError.decodingFailed("No scan data found in JPEG")
        }
        guard frame.isLossless else {
            throw JLIError.unsupportedJPEGFeature("the shared surface decodes the lossless SOF3 path only")
        }
        return try decodeLossless(
            frame: frame, scans: parsed.scans, configuration: configuration,
            restartInterval: parsed.restartInterval,
            iccProfile: parsed.iccProfile, exif: parsed.exif,
            borrowedDestination: plane)
    }
}

/// The one interleave path, used by both the array and borrowed branches so
/// they cannot drift.
@inline(__always)
func jliWriteInterleavedPlanes(
    from planeBase: UnsafePointer<Int32>,
    into dst: UnsafeMutableRawBufferPointer,
    width: Int, height: Int, rowSamples: Int,
    componentCount nc: Int, samplesPerPlane count: Int,
    bytesPerSample bps: Int, pointTransform pt: Int
) throws {
    guard let d = dst.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
    for c in 0..<nc {
        let src = planeBase + c * count
        for y in 0..<height {
            try NativeOperation.check()
            let rowBase = y &* rowSamples
            let inRow = y &* width
            if bps == 1 {
                for x in 0..<width {
                    d[rowBase &+ x &* nc &+ c] = UInt8(clamping: Int(src[inRow &+ x]) << pt)
                }
            } else {
                for x in 0..<width {
                    let v = UInt16(clamping: Int(src[inRow &+ x]) << pt)
                    let o = (rowBase &+ x &* nc &+ c) &* 2
                    d[o] = UInt8(v & 0xFF)
                    d[o &+ 1] = UInt8(v >> 8)
                }
            }
        }
    }
}

// The public adapter preflights and parses once, then writes into its lease.
extension JLIDecoder {
    func decodeSharedLossless(_ parsed: ParsedJPEG, into plane: BorrowedSampleDestination,
                              useScalarCEntropy: Bool = false) throws {
        _ = try decodeLossless(frame: parsed.frameInfo, scans: parsed.scans,
            configuration: .init(outputPixelFormat: plane.bytesPerSample == 1 ? .uint8 : .uint16),
            restartInterval: parsed.restartInterval,
            iccProfile: parsed.iccProfile, exif: parsed.exif, borrowedDestination: plane,
            useScalarCEntropy: useScalarCEntropy)
    }
}
