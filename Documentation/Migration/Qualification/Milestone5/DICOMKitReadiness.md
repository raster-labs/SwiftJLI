# DICOMKit adoption readiness — 3 November 2026

**Disposition: source audit and migration plan complete; actual DICOMKit integration is unexecuted.** The current DICOMKit consumer uses predecessor-specific managed decoding APIs that SwiftJLI does not expose. Replacing the package dependency and renaming API calls would not preserve that consumer's allocation and execution contract.

This record belongs to SwiftJLI Milestone 5 release preparation. DICOMKit source changes, consumer release acceptance and its coordinated four-codec cutover remain separate work under [suite policy Decision D3](../../../SUITE_POLICY.md#contract-revision-090--22-september-2026). SwiftJLI remains an independent JPEG codec; DICOM parsing, transfer-syntax policy, patient metadata and display transformations stay in the consumer.

## Inspected source and method

| Item | Exact source |
| --- | --- |
| Consumer repository | [raster-labs/DICOMKit](https://github.com/raster-labs/DICOMKit) |
| Consumer snapshot | [`ff9d26fc6336340f7a5046419d9ac164e341eb0d`](https://github.com/raster-labs/DICOMKit/tree/ff9d26fc6336340f7a5046419d9ac164e341eb0d), default branch `main`, retrieved on 3 November 2026 |
| Resolved JPEG predecessor | JLISwift `0.6.0`, [`b6df774a3c3ecdf4b98971f31543fdd18074ace2`](https://github.com/raster-labs/JLISwift/commit/b6df774a3c3ecdf4b98971f31543fdd18074ace2), recorded in the consumer's `Package.resolved` |
| SwiftJLI comparison snapshot | `8ae2762710d6279cd92222f5bb5ca95f042f694e`; suite policy `0.10.0` |
| Method | GitHub connector repository discovery, manifest/source reads and a fresh shallow clone for a read-only source audit; no dependency resolution, build, test, benchmark or consumer mutation |

No local DICOMKit checkout was found under the inspected project roots. The connected GitHub repository resolved the historical `Raster-Lab/DICOMKit` name to `raster-labs/DICOMKit`; a fresh clone confirmed the commit above. No `AGENTS.md` or `CLAUDE.md` was present in the retrieved tree. The audit checkout was clean after inspection.

Executed source retrieval and identity checks, all successful:

```sh
git clone --depth 1 https://github.com/raster-labs/DICOMKit.git <fresh-audit-directory>
git -C <fresh-audit-directory> rev-parse HEAD
git -C <fresh-audit-directory> status --short
```

The exact source hashes retained from that checkout are:

| Path | SHA-256 |
| --- | --- |
| `Package.swift` | `87bd10a1c470169c65574446c534d25aca144e6402618fcee370ad133b543f30` |
| `Package.resolved` | `f42c82a74f4a24ff353f3d8c5df4e9893f11dab9514bdd6e57335dd105eb5500` |
| `Sources/DICOMCore/JLICodec.swift` | `38c01ffa838e78ff5c92154ec137a811365b31c5517fbde8851e3b573c61db0e` |
| `Sources/DICOMCore/ImageCodec.swift` | `a594e77140f6ff441af4467a4edf798fcf997ded6e4e79326e7ec655e4edc215` |
| `Documentation/BoundedInput/AllocationContract.md` | `06a74aeb0999b9b577af9dbad33eb78af64fe452c1e117992842e50c9ecd6445` |

## Current consumer facts

The inspected [manifest](https://github.com/raster-labs/DICOMKit/blob/ff9d26fc6336340f7a5046419d9ac164e341eb0d/Package.swift) requires Swift tools **6.4** and declares iOS 18, macOS 15, tvOS 18 and visionOS 2. JLISwift is already pinned exactly to **0.6.0**. DICOMCore depends on the `JLISwift` product only: the historical `JLIDICOM` product dependency has already been removed. A nearby comment still describes both predecessor products, but no `JLIDICOM` product dependency or import is present. The September inventory in SwiftJLI's historical records must not be used as current consumer state.

`Sources/DICOMCore/JLICodec.swift` is the only direct `import JLISwift` in the inspected consumer's `Sources/` and `Tests/` trees. Its public `ImageCodec` and `ImageEncoder` requirements are synchronous. It supports registered JPEG Baseline `.4.50`, Extended `.4.51`, Lossless `.4.57` and Lossless SV1 `.4.70` routes with explicit process/descriptor checks. This is a statement of the inspected implementation and tests, not a new interoperability result.

The consumer keeps two distinct paths:

- The compatibility path returns `Data`, reconstructs the actual output descriptor, can widen decoded 8-bit samples into 16-bit storage, and performs DICOM planar/interleaved conversion.
- The managed path owns encoded input, workspace, final storage and control capacity through `DICOMAllocationBudget`, executes on an admitted synchronous worker, and uses scalar failure outcomes and borrowed synchronous cancellation. Its supported profiles are deliberately narrower.

See [the current adapter](https://github.com/raster-labs/DICOMKit/blob/ff9d26fc6336340f7a5046419d9ac164e341eb0d/Sources/DICOMCore/JLICodec.swift) and [the consumer allocation contract](https://github.com/raster-labs/DICOMKit/blob/ff9d26fc6336340f7a5046419d9ac164e341eb0d/Documentation/BoundedInput/AllocationContract.md).

## Compatibility findings and required treatment

| Area | Current consumer requirement | SwiftJLI adoption work or limitation |
| --- | --- | --- |
| Dependency/platform | Consumer still uses all four predecessor packages and pre-26 Apple deployment floors. | Coordinate the four successor dependencies and raise supported Apple floors to 26.0 in the separately assigned consumer task. The consumer already requires Swift 6.4; no compiler-floor reduction is implied. |
| Execution | `ImageCodec.decodeFrame`, `decodePixelFrame` and `ImageEncoder.encodeFrame` are synchronous. | SwiftJLI `Encoder.encode` and `Decoder.decode` are asynchronous `@concurrent` APIs. Design the consumer execution boundary explicitly; a semaphore wrapper or escaped borrowed pointer is not a qualified migration. |
| Managed allocation — adoption blocker | `decodeManagedPixelFrameOutcome` uses `inspectLosslessMonochromeCore`, `decodeLosslessMonochromeCore`, `inspectBaselineRGBCore`, `decodeBaselineRGBCore`, caller workspaces and `JLICoreFailure`. The admitted worker is synchronous; all retained capacities are charged to one ledger. | SwiftJLI's public owning-storage API does not expose equivalent caller-workspace, scalar-outcome or whole-stack admission APIs. `ResourceLimits` and `decode(_:into:)` do not establish those stronger guarantees. Preserve the qualified predecessor route until a separately designed and tested successor solution exists; do not silently route managed decoding through the compatibility API. |
| Sample precision | DICOM dimensions, components and `bitsStored` must equal the JPEG header; the current strict decoder requires `highBit == bitsStored - 1`. | Set `meaningfulBits` explicitly and preserve those checks. Test 8-bit data in both 8- and 16-bit allocated storage, 12-in-16 and full 16-bit values. SwiftJLI can write compatible wider caller storage directly; verify exact samples, storage identity and padding. |
| Signed lossless pixels | The registry includes signed 16-bit lossless acceptance, with signed interpretation retained in DICOM metadata. | SwiftJLI rejects signed image descriptors and returns unsigned JPEG sample words. Any bit-pattern mapping needs an explicit consumer metadata contract and tests of signed extrema, sign extension and narrower stored precision. Merely changing the descriptor to unsigned is not acceptance. |
| Layout and ownership | Consumer input may be planar; managed buffers are noncopyable and borrowed synchronously. | SwiftJLI's codec path currently requires interleaved little-endian sample storage. Qualify any deliberate conversion and its allocation/copy cost. A provider must own sealed storage for the complete asynchronous operation; a raw pointer borrowed from `DICOMByteBuffer` cannot become an asynchronous owner. |
| Colour | DCT output is RGB; source selection considers JPEG markers and DICOM photometric interpretation. SOF3 preserves the consumer's external interpretation. | Pass `DecoderConfiguration.sourceColourModel` only on the supported unmarked three-component DCT route; marked JPEG must use its signalling. Explicitly qualify RGB/YBR metadata and planar conversion. Lossless YBR data must not be silently relabelled as RGB to satisfy the generic API. |
| Encoding/process | Both lossless UIDs use predictor 1 and point transform 0. Baseline colour uses sequential 4:2:2; Extended colour is rejected. Eight-bit Extended output is promoted to SOF1 by the consumer. | Map to explicit `.lossless` / `.lossy`, `CodecOptions(predictor: 1)` and sequential `DCTOptions`. Preserve JFIF removal, the qualified eight-bit SOF1 promotion and lossless/lossy DICOM metadata. Do not infer process equivalence from the generic JPEG format name. |
| Errors, limits and cancellation | Managed outcomes preserve scalar failure domains and synchronous cancellation. Compatibility decoding validates finite input/pixel/output limits. | Map the existing budgets explicitly; SwiftJLI defaults are not the consumer defaults. Preserve cancellation and refusal semantics. Managed scalar transport remains part of the unresolved allocation/execution design. |
| Frame/container semantics | Encapsulated fragment assembly, source frame identity, descriptors and final Pixel Data metadata are consumer responsibilities. | Pass one validated JPEG frame per codec operation. Retain frame/fragment, offset-table, truncation and source-descriptor checks in DICOMKit; SwiftJLI is not a DICOM parser or multi-frame container API. |

The managed predecessor API dependency is visible at [JLICodec.swift lines 291–429](https://github.com/raster-labs/DICOMKit/blob/ff9d26fc6336340f7a5046419d9ac164e341eb0d/Sources/DICOMCore/JLICodec.swift#L291-L429). The consumer's contract explicitly forbids an uncharged legacy fallback and retains complete backing capacity after handoff. SwiftJLI's present `peakWorkspaceBytes == nil` reporting must not be represented as zero workspace or complete application allocation accounting.

## Consumer acceptance plan — unexecuted

1. Pin the selected DICOMKit and all four successor revisions. Record the existing consumer's passing, failing and skipped tests before changing adapters, and retain its dependency lock and rollback path.
2. Resolve the synchronous execution and managed allocation blockers in a separately assigned design. Preserve the existing admitted worker, buffer-owner lifetime, scalar refusal and complete-capacity accounting guarantees, or obtain an explicit consumer contract change before changing those guarantees.
3. Implement the adapter and package changes in an isolated DICOMKit branch. Keep DICOM parsing and metadata policy in DICOMKit. Preserve current transfer-syntax/process restrictions and the existing `JLIDICOM` cleanup.
4. Execute predecessor/candidate comparisons over registered Baseline, Extended, Lossless and SV1 cases, including odd/non-square dimensions, 8/12/16-bit extrema, signed interpretation, 8-in-16 allocation, planar RGB, YBR input, supported marker signalling and negative cases. Lossless samples and required external interpretation must match exactly; lossy cases need independently justified fixed tolerances. Retain independent codec fixtures rather than relying only on round trips.
5. Run complete source/frame/descriptor, fragment/offset-table, failure/cancellation, memory/copy/lifetime, concurrent-reader and managed admission/ownership tests. Verify allocator/control ownership outside sanitizers, and separately run lifetime/race checks under appropriate sanitizers. Preserve correct lossless flags, compression metadata, output photometric interpretation and source frame indices.
6. Qualify the supported consumer platforms, clean URL dependency resolution, affected CLI and rendering/compression workflows, and the combined memory budget. Publish exact results and exclusions before enabling the successor route. Neither this source audit nor SwiftJLI's internal DICOM helpers replace those consumer runs.

Existing test groups to retain include `JLICodecRegistryTests`, `StrictCompressedFrameTests`, `IndependentCompressedFrameTests`, `M7JPEGExtendedProcessTests`, `ManagedCodecTests`, `DICOMAllocationBudgetTests`, `DICOMExternalAllocationTests`, `EncapsulatedPixelDataOffsetTableTests`, `CompressionManagerJPEGEngineTests`, `CompressionManagerPhotometricInterpretationTests` and `LossyImageCompressionAttributesTests`. Their source is present in the pinned consumer; none was executed in this audit.

For the separate consumer task, a focused starting command is:

```sh
swift test --filter 'JLICodecRegistryTests|StrictCompressedFrameTests|IndependentCompressedFrameTests|M7JPEGExtendedProcessTests|ManagedCodecTests|DICOMAllocationBudgetTests|DICOMExternalAllocationTests|EncapsulatedPixelDataOffsetTableTests'
```

This is a proposed command, not executed evidence or the complete consumer acceptance matrix.

## Limits of this Milestone 5 evidence

SwiftJLI's [encapsulated DICOM test](../../../../Tests/SwiftJLITests/Native/DICOMWriterTests.swift) uses internal test-only `DICOMReader` and `DICOMWriter` helpers. Its presence establishes a regression target for JPEG/container interoperability; it does not link or test the external DICOMKit package. This audit adds current consumer source evidence and a concrete migration plan only. No consumer dependency, runtime behaviour, performance, memory consumption or supported platform has changed, and no DICOMKit cutover is claimed.
