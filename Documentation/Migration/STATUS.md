# Codec migration status — 7 October 2026

Migration remains in progress. This checkpoint does not establish first-stable readiness.

Source: JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Successor base: `41b3cbc34e5e96db41853c925ec720fad4120b65`. Common suite policy: 0.10.0; shared contract documents are unchanged. Per-file origins and original hashes are in [provenance.json](provenance.json).

## Implemented checkpoint

The public Encoder/Decoder use the migrated native SOF3 kernel for unsigned 2–16-bit greyscale and explicit RGB. Lossless encoding fixes point transform to zero. Explicit near-lossless requests select the largest JPEG point-transform error bound (2^Pt − 1) no greater than the caller maximum and legal for the sample precision; the encoded result and fidelity report state the effective bound. Predictor 1–7 and row-aligned restart intervals are explicit controls. Packed little-endian 8/16-bit samples, padded rows and prefix offsets are supported. Other layouts currently fail even with allowCopy; no hidden repack is performed. Signed/float/alpha requirements are rejected.

Encoding borrows sealed source storage. Both decode call shapes use the same direct destination writer; a supplied destination incurs no second final image. Native Int32 planes/residuals remain algorithm workspace (8 bytes/sample on encode, 4 on decode, plus entropy, tables and compressed storage). Admission currently reserves conservative additional overhead: encode 64 bytes/sample + 4×metadata + 1 MiB, decode 8 bytes/sample + 64×compressed input + 1 MiB. These are admission bounds, not measured peak figures. Peak workspace reports remain unknown pending allocator measurement. Tight budgets can reject operations below their actual peak.

Each public lossless operation executes serially within its task, satisfying the worker ceiling without detached work. Row checks and bounded entropy-loop checks preserve cancellation/deadline errors. The native parallel implementations remain internal and covered by predecessor regression tests; public parallel lossless dispatch is not yet qualified.

ICC colour interpretation is retained, including under discardAncillary. Exif maps to ImageMetadata.entries["Exif"]. Unknown required metadata, unsupported marker semantics and incompatible destinations fail explicitly. Structural inspection does not certify entropy validity.

## Executed evidence

- Predecessor CI [35524297254](https://github.com/raster-labs/JLISwift/actions/runs/35524297254): succeeded at the pinned baseline.
- Successor pre-migration CI [37630552591](https://github.com/raster-labs/SwiftJLI/actions/runs/37630552591): all seven jobs passed, clearing the source-move prerequisite. This is baseline evidence, not migrated-code qualification.
- Linux ARM64, `swift:6.4-noble` digest `sha256:31d14d727f4451f25e29bac9c42563a098c39ac66415e8bad970f48038e38aca`: `swift test --scratch-path .build-linux -j 4` passed 212 tests in 22 suites. The test count does not count each parameter case separately.
- Local macOS ARM64/Swift 6.4: `swift build --disable-sandbox` passed. Local tests cannot load the CommandLineTools TestingMacros plug-in; macOS test/sanitizer qualification is delegated to CI.
- Diagnostic CLI: `Scripts/test-cli.py` passed 107 process checks, including real capability JSON, reserved verbs, streams and manual installation.
- libjpeg-turbo 3.2.0 (20260630): 105 cases (precisions 2–16 × predictors 1–7, two-row restart interval) passed in both directions. Its djpeg decoded SwiftJLI output sample-exactly, and the public decoder decoded independent cjpeg output sample-exactly. These are generated synthetic samples, with no patient data or external fixtures.

Reproduce independent interoperability from the repository root:

```sh
python3 Scripts/verify-lossless-interop.py --output-dir /tmp/swiftjli-oracle --scratch-path /tmp/swiftjli-oracle-build
```

The script requires installed lossless-capable cjpeg/djpeg and a compatible Swift toolchain. These are development-only oracles, never runtime fallbacks. Embedded predecessor oracle fixtures remain in the native regression tests with their original provenance comments.

## Corpus and bounded-error extension

- Restored frozen regression/conformance cases, all predecessor test files, shared-storage lifecycle assertions, and benchmark synthetic generators/identity helpers. DICOM helpers live only under Tests; the shipping dependency graph still has no DICOM product. Three Accelerate window-comparator tests remain Apple-only; portable container/codec tests run on Linux. Test names inherited from the predecessor are engineering assertions, not medical/regulatory certification.
- Generated a 71-record identity snapshot by actually running JLIBench from the source pin on macOS 27.0.1 ARM64 / Apple Swift 6.4 (swiftlang-6.4.0.34.1). The migrated native kernels produced a byte-identical record file, aggregate `0e347394a1a9ae7170857ed54e2de2d8bed891184172a8fa36c6471b2d19800a`. Integer SOF3 records are asserted across platforms; the complete DSP-dependent matrix is asserted on Apple ARM64. Linux lossy qualification continues to use its regression/oracle tolerance tests, not Apple floating-point hashes.
- Expanded Linux Swift 6.4 suite: 288 tests in 31 suites passed. Added near-lossless public tests at 2/8/12/16 bits with canonical/noncanonical/extreme requested error bounds, all seven predictors, and shared destinations. The test-only SHA-256 implementation matches frozen predecessor fixture hashes and known vectors; it is not part of the codec product.
- Independent oracle now checks 210 profiles in each direction, adding nonzero point transforms to the original 105 lossless profiles. Both directions match the exact expected quantised samples with libjpeg-turbo 3.2.0.
- CI run 37634191261 passed all Linux jobs and the independent consumer, but the larger native suite starved a global-queue ownership test. The test now uses a dedicated competing thread while retaining both exclusion assertions. Run 37635163228 then passed macOS ordinary tests and ASan, but TSan found zero-capacity unsafe array initialisers writing Swift's shared empty-array storage. The decoder now chooses `[]` before those initialisers; a concurrent DCT/scale regression was added. The fix still requires a clean macOS TSan run.

Verify that every predecessor principal-source/test path has a migrated or retired disposition and that original/fixture hashes agree:

```sh
python3 Scripts/verify-provenance.py --predecessor /path/to/JLISwift
```

## DSP backend preparation

Scalar vector/matrix primitives now remain available on Apple as well as Linux. Operation context selects the scalar reference; legacy native calls retain their Accelerate default on Apple. Operation-owned native work stays on its invoking task, so Dispatch workers cannot lose the selected backend. The subsequent DCT integration below connects this selection to the public API.

A direct Accelerate comparison found half-way byte conversions use nearest-even rounding: `[0.5, 1.5, 2.5, 3.5]` becomes `[0, 2, 2, 4]`. The scalar conversion now agrees. Tests cover rounding, matrix dimensions/strides and DCT accuracy. Linux Swift 6.4 passes 291 tests in 31 suites. The local macOS build passes; scalar/Accelerate reconstruction passed the 0.001 sample-unit tolerance and the tested block's maximum coefficient difference was 0.000015258789. Re-running the native identity harness still matches all 71 predecessor records exactly.

## Public DCT integration

The common API now encodes/inspects/decodes SOF0/SOF1/SOF2 at unsigned 8/12-bit precision. `DCTOptions` exposes quality/distance, 4:4:4/4:2:2/4:2:0, sequential/spectral-selection/successive-approximation scripts, optimal Huffman tables, trellis quantisation and perceptual tables. Lossy mode remains explicit. DCT source reads and final writes use scoped caller storage, including padded rows. Float component/coefficient planes are workspace, with a row of colour scratch; there is no additional packed final image.

Apple DCT uses selectable Accelerate; scalar remains selectable everywhere. SOF3 required-accelerated requests still fail. Parser validation covers scan/table topology, approximation order and supported colour/sampling. Chroma rows, MCU rows, DCT/reconstruction chunks and trellis chunks check cancellation. DCT admission reserves 192 bytes/source sample on encode and 128 bytes/sample plus 64×compressed bytes on decode, with the existing 1 MiB and metadata allowances. These deliberately conservative reservations are not measured peaks and can reject large images under default limits.

Executed at this checkpoint:

- Linux ARM64 Swift 6.4: **297 tests in 33 suites passed**, including public DCT mode/storage/backend checks, byte mutations/truncations and deadline/cancellation errors.
- Native borrowed/packed comparison: 8/12-bit × greyscale/RGB × all three chroma settings × all three scan modes × both backends; encode bytes match, decode samples match at scales 1/2/4/8, padding remains untouched. The matrix passed on Linux and in a local macOS executable harness.
- Independent libjpeg-turbo 3.2.0: **24 DCT profiles in both directions**, greyscale and 4:4:4 RGB, 8/12-bit, all three encoder scripts and scalar/automatic selection. Maximum Float/integer IDCT difference was **2 sample units**. `Scripts/verify-dct-interop.py` reproduces this check; subsampled colour remains covered by native identity/matrix tests rather than this oracle tolerance.
- All **71** pinned-predecessor native identity records still match exactly on macOS ARM64.
- Local macOS 27.0.1 / Swift 6.4 executable harness passed **AddressSanitizer and ThreadSanitizer** (both exit 0) over the identity matrix, borrowed DCT matrix and 24 tasks × 4 iterations × 4 decode scales. This is targeted native validation; it is not the full Swift Testing suite or macOS 26/Swift 6.2 qualification.
- Diagnostic CLI: **107 process checks passed** with the expanded capability JSON. Provenance verification still accounts for every pinned principal-source/test path.
- CI run [37639488932](https://github.com/raster-labs/SwiftJLI/actions/runs/37639488932) passed four Linux jobs, the independent consumer and contract hashes at the previous DSP checkpoint. Its macOS job was cancelled before a runner started. The DCT commit requires a fresh CI run.

Reproduce the independent DCT oracle:

```sh
python3 Scripts/verify-dct-interop.py --output-dir /tmp/swiftjli-dct-oracle --scratch-path /tmp/swiftjli-dct-build
```

## Exploratory release comparison

A two-package local harness compared the actual pinned predecessor with the public successor on deterministic 512×512 RGB8 and greyscale12 images. Three warm-ups, eight timed iterations and alternating implementation order produced the following upper medians. Both JPEG outputs were byte-identical for these inputs. [Harness](Benchmarks/Comparison.swift) and [raw timing/source hashes](Benchmarks/results.json) are retained.

| Profile | Predecessor encode | Successor encode | Predecessor decode | Successor decode |
| --- | ---: | ---: | ---: | ---: |
| RGB8 / 4:2:0 | 5.146 ms | 6.624 ms | 3.562 ms | 4.177 ms |
| Greyscale12 | 2.938 ms | 3.344 ms | 2.589 ms | 3.387 ms |

The first RGB direct writer was substantially slower; vectorised byte reads/final writes reduced its measured decode median from 7.212 to 4.177 ms. A gap remains: about 14–29% for encode and 17–31% for decode on these samples. Full-frame working memory is still unmeasured. These are provisional measurements, not acceptance: background load was not isolated, and both local release build engines produced runnable binaries but hung after linking and were interrupted (exit 130). Executing the final native-engine release binary exited 0. Clean build completion, controlled broader datasets and platform-specific performance remain required.

## Remaining migration requirements

- Qualify and expose remaining advanced profiles: XYB/ICC interpretation, explicit float semantics, advanced adaptive fields and decoder output/scale controls. The common adapter currently rejects unsupported profiles.
- Qualify public DCT backend performance and resource instrumentation. Backend selection and direct storage are now implemented; full platform qualification remains open.
- Complete public-mode coverage of the retained regression corpus as lossy integration lands. All predecessor test files are now represented; the six duplicate contract files and predecessor module/version overview are explicitly retired in provenance.
- Complete parser/entropy security review, mutation/resource/cancellation tests, fuzzing, sanitizers and native platform/SDK coverage.
- Measure memory/copy instrumentation and release performance against the pinned predecessor; qualify the shared-storage cross-codec extension.
- Finish documentation, independent versioned consumption and the full acceptance audit. CLI payload verbs remain separately budgeted new work under IMPLEMENTATION.md I3; diagnostic capabilities already read the real library values.

No predecessor release, consumer cutover, archive, stable successor tag or merge has been performed by this checkpoint.
