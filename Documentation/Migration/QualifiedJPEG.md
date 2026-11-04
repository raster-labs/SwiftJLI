# Synchronous caller-storage JPEG subset

This API is integration work for DICOMKit's admitted synchronous decoder. It supplements the common owning `Decoder`; it does not replace it or change its default behaviour. Contract 0.10.0/API-13 permits the specialised operation because an async owning `Image` cannot describe a borrowed worker reservation, fixed scalar failure transport and a full caller-admitted RGB arena.

The explicit profile is `QualifiedJPEGDecoder.Profile.jliswift060`, pinned to [JLISwift b6df774a3c3ecdf4b98971f31543fdd18074ace2](https://github.com/raster-labs/JLISwift/commit/b6df774a3c3ecdf4b98971f31543fdd18074ace2). It retains the predecessor ceiling of 16,777,216 pixels and 65,535 per dimension, even if caller limits are larger. It supports 2–16-bit SOF3 monochrome into packed little-endian UInt16 and SOF0 three-component sequential JPEG into RGB8. Full-resolution output only; progressive, SOF1, other component counts, scale requests and owning metadata are outside this interface. DICOM signedness and photometric interpretation remain the consumer's explicit external context.

```swift
let decoder = SwiftJLI.QualifiedJPEGDecoder(profile: .jliswift060,
    limits: .init(maximumEncodedBytes: admittedInputLimit,
                  maximumPixels: admittedPixelLimit,
                  maximumDecodedBytes: admittedLogicalOutputLimit),
    sourceColourModel: .yCbCr)
// These spans are borrowed from caller-owned admitted storage on one worker.
let plan = decoder.inspectBaselineRGB(encoded, headerWorkspace: header)
// After success, admit info.workspaceByteCount and info.arenaByteCount.
let result = decoder.decodeBaselineRGB(encoded, arena: arena, workspace: workspace)
```

Allocation qualification is specific to the recorded optimised Release toolchain and build. A fresh Debug cold-XYB probe allocated; Debug and sanitizer correctness tests do not establish an allocation-free worker. Consumers requiring strict worker admission must qualify their complete optimised build and callbacks. The public operation still uses caller-owned payload/control records in every configuration.

The caller must keep input immutable, all spans disjoint, and output/workspace exclusive until synchronous return. Workspace and RGB arena require `workspaceAlignment`; their raw trivial storage changes binding. Cancellation is a thin C function/context borrow, deliberately not Sendable. The caller retains and synchronises that context, and callbacks must not access mutable scratch/output or mutate input. Callback allocations, worker/bootstrap/runtime infrastructure and stack admission remain caller responsibilities. No pointer is returned or retained and no task is created. Every failure invalidates output, including partially written samples; the same storage may be reused after return.

Lossless workspace is 6,160 bytes on supported targets; the decoder reconstructs in the final little-endian words. Baseline inspection needs 16,384 bytes. For N pixels its retained arena is 12N bytes (three Float planes), and its RGB result occupies the first 3N bytes. The complete arena must remain admitted and retained for the result lifetime. Scratch is a bounded MCU-row coefficient strip, supplied Huffman/parser tables, IDCT buffers, three cached rows and a 1,024-pixel conversion tile. `BaselineRGBInfo` supplies its exact size. MaximumDecodedBytes bounds logical published samples; maximumMemoryBytes counts complete input, output/arena and workspace capacities, and maximumWorkspaceBytes bounds complete scratch capacity. Arithmetic and dimensions are checked before image work. Each operation parses the structure once; decode repeats inspection independently rather than trusting a previous call. Dimension and scratch admission occur in the shared plan before sample writes. Each public operation has its own finite monotonic deadline, including a saturating representation for huge finite values.

The profile preserves missing-Huffman-table defaults, lossless category16/modulo arithmetic, point-transform serialisation, per-scan DHT/DQT/DRI snapshots, chroma-centre sampling, raw RGB and canonical XYB detection/conversion. Ancillary payloads are scanned in place and not returned. It retains the predecessor's permissive accepted RST-number policy; inspection is not a conformance certificate. The narrower SOF0/SOF3 boundary, invalid DHT-class rejection, duplicate frame-component rejection, missing referenced DQT refusal (scalar code178, before output writes), and invalid lossless scan-component/parameter rejection are explicit stricter boundaries, not silent fallback. Cancellation is checked during parsing, at row/sample/MCU/tile boundaries and before successful publication. Reconstruction tiles contain at most 64 blocks.

## Source extraction

All paths below are relative to predecessor `Sources/JLISwift/` at the pinned SHA. Adapted files retain Apache-2.0 notices. No old package dependency, encoder, Metal backend, common owning decoder, throwing compatibility facade or Array/Dictionary parser branch is imported. Internal pointer carriers have no unchecked Sendable conformance.

| Predecessor sections | Successor `Sources/SwiftJLI/Qualified/` |
| --- | --- |
| Decoder/JLILosslessCallerStorage.swift, JLILosslessParseStorage.swift | QualifiedLosslessCallerStorage.swift, QualifiedLosslessParseStorage.swift |
| Decoder/JLIBaselineCallerStorage.swift, JLIBaselineParseStorage.swift | QualifiedBaselineCallerStorage.swift, QualifiedBaselineParseStorage.swift |
| Decoder/JLICoreStorage.swift borrowed records and fixed triple | QualifiedStorage.swift |
| Markers/JLIMarkerReader.swift borrowed grammar/headers; Markers/JLIMarkerWriter.swift marker constants | QualifiedParser.swift, QualifiedHeaders.swift, QualifiedMarkers.swift |
| Entropy/JLIBitStream.swift borrowed reader; Entropy/JLIHuffman.swift decode-only kernels, literal defaults, caller table compiler | QualifiedBitReader.swift, QualifiedHuffman.swift |
| Decoder/JLIDecoder.swift lossless validation/prediction and supplied-table block reconstruction | QualifiedKernels.swift |
| Platform/AccelerateBackend.swift supplied-table pure Swift SIMD IDCT and scalar colour overloads; DSP/JLIQuantization.swift table fills | QualifiedReconstruction.swift, QualifiedQuantization.swift |
| ColorSpace/JLIChromaSampling.swift in-place borrowed upsampling; ColorSpace/JLIXYBICCProfile.swift read-only literal profile | QualifiedChroma.swift, QualifiedXYBProfile.swift |
| Core/JLICoreFailure.swift scalar fields; Decoder/JLICoreStorage.swift cancellation; new explicit limits/deadlines/admission | QualifiedOutcome.swift, QualifiedJPEGDecoder.swift |

The pure scalar `ColorConversion.xybSampleToRGB` already present in SwiftJLI is reused without editing it. Despite the predecessor's `AccelerateDSP` name, the extracted supplied-table functions call no Accelerate framework, owning static arrays, TaskLocal or worker runtime. Literal XYB profile material retains its existing repository attribution; it is not relicensed by this extraction.

## Validation boundary

The isolated noncopyable-owner/C-callback adapter probe compiled and ran before extraction. The pinned predecessor's three caller-storage suites passed 17 tests. New tests reuse the retained independent libjpeg lossless and chroma fixtures, with exact lossless samples and the established chroma regression bound of three. This is separate from the historical performance corpus's threshold of two and does not change its exclusions.

Current implementation checks, source hashes, failed development attempts and command receipts are retained under the dedicated qualification directory when complete. A source review, a successful unit test, or a prepared allocation probe alone is not proof of zero allocations, whole-worker admission, physical-device performance or completion of DICOMKit integration. Required consumer/platform/fuzz/performance requalification remains separately recorded.
