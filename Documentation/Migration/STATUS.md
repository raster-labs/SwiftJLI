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

## Output and adaptive profile extension

Public decoder configuration now exposes native DCT scales 1/2/4/8 and an explicit `.float32RawSamples` profile for greyscale DCT without ICC. Raw floats preserve the native reconstructed sample units and exact Float32 bit patterns; they are not implicitly normalised. Both allocating and caller-owned output support the same profiles. Inspection retains encoded geometry/precision. Capabilities now describe the queried encoder/decoder operation, including decode-only Float32 support. Preview admission counts full-frame coefficients, not only the smaller result.

Public DCT options now expose the retained adaptive trellis field and jpegli masking/zero-bias path. Incompatible combinations and 12-bit requests for these 8-bit algorithms fail before source borrowing. Added row/block cancellation checks cover field computation and reduced-scale dequantisation.

Evidence:

- Linux ARM64 / Swift 6.4: **303 tests in 36 suites passed**, including native/public equality, padded ownership, raw float units, rejected interpretations and preview workspace limits.
- Local macOS ARM64 / Swift 6.4: new profile matrices passed on scalar and Accelerate in the executable harness; ASan and TSan both exited 0. All 71 pinned native identity records remain identical.
- The independent DCT oracle now covers **48 profiles in each direction**, adding both adaptive paths for 8-bit greyscale/RGB. Maximum difference remains **2 sample units** against libjpeg-turbo 3.2.0. The 12-bit profiles retain their non-adaptive quantisation behaviour.
- CI [37645149130](https://github.com/raster-labs/SwiftJLI/actions/runs/37645149130) passed all seven jobs at `bcd1201`, including the full macOS 26 / Apple Swift 6.3.3 test, ASan and TSan suite (the old job label incorrectly said 6.2). This closes the earlier empty-array scratch race check at that revision. The new output/adaptive changes still require their own head CI.
- `Scripts/build-apple-sdks.sh` adds release compilation of the library for iOS/tvOS/watchOS/visionOS devices and ARM64 simulators, plus Intel macOS. Its syntax is checked locally; execution requires full Xcode and is a new CI gate, not yet passed evidence. macOS CI also gains release build/tests. These compile gates do not replace device/runtime coverage.

## Shared DCT storage mutation evidence

`Scripts/verify-storage-mutations.py` creates a disposable source copy and deliberately breaks the borrowed DCT reader/writer. On Linux ARM64 / Swift 6.4, the unchanged `SharedDCTStorageTests` matrix passed; all four mutants compiled and failed executed expectations. Compiler failures do not count as detected mutations. The matrix covers 8/12-bit, greyscale/RGB, chroma/scan modes and decode scales, with distinct source/destination padding.

| Deliberate defect | Test issues | Expectation-failure messages | Caught-error messages |
| --- | ---: | ---: | ---: |
| Encoder ignores source row stride | 40 | 38 | 2 |
| Encoder reverses 16-bit byte order | 4 | 2 | 2 |
| Decoder ignores destination row stride | 1422 | 1405 | 0 |
| Decoder reverses 16-bit byte order | 144 | 144 | 0 |

Swift Testing's total issue count and rendered message counts are recorded separately; grouped/parameterised diagnostics do not always render one message per issue. [Machine-readable evidence](StorageMutations/results.json) pins the source/test hashes, compiler, container image, exit codes and log hashes at `fc02b48`. Logs are regenerated by the command below. The original checkout is never mutated. This proves the DCT assertions detect these injected defects; it does not replace allocator telemetry, predictive-path mutation checks or other TEST-09 requirements.

```sh
python3 Scripts/verify-storage-mutations.py --docker-image swift:6.4-noble --output-dir /tmp/swiftjli-storage-mutations
```

## Explicit Float32 input and SDK correction

The public DCT encoder now accepts normalised little-endian Float32 greyscale/RGB only with `floatInputPolicy: .normalisedClampedToUInt8` in explicit lossy mode. Finite samples clamp to [0,1], scale by 255 and round to nearest/ties-away; NaN and infinities reject. Quantisation is fused into the borrowed source reader, with no intermediate UInt8 image. `OperationReport.sampleConversion` records the value mapping independently from copy accounting. Integer input rejects the float-specific policy. The emitted JPEG remains 8-bit; raw Float32 decoder output must not be mistaken for normalised encoder input.

- Linux ARM64 / Swift 6.4: **305 tests in 37 suites passed**. New tests compare encoded bytes against independently specified integer quantisation results at endpoints, half-way values and out-of-range clamps; NaN-filled padding verifies row addressing. Ordinary lossy/default lossless policies and non-finite samples reject.
- Local macOS ARM64 / Swift 6.4: Float32 input matrices passed scalar/Accelerate, plus ASan and TSan executable harnesses (exit 0). All 71 native identity records still match the executed predecessor file byte-for-byte. The independent public consumer also passed.
- SDK run [37649435202](https://github.com/raster-labs/SwiftJLI/actions/runs/37649435202) completed the first five SDK builds, then failed at the watchOS arm64_32 target because imported `vDSP_Stride` is Int64 while Swift Int is 32-bit. Every Accelerate wrapper now converts strides explicitly. The SDK script prints each target and SDK version; the correction requires another CI run. Later SDK targets were not reached.
- The macOS runner logs identify **Apple Swift 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101), Xcode 26.6 (17F113)**, including the earlier successful bcd1201 run. The previous 6.2 job name was inaccurate; workflow naming and the latest evidence above now reflect the actual toolchain. Linux CI independently covers Swift 6.2 and 6.4. This is not proof of Apple Swift 6.2 runtime qualification.

## Public XYB and ICC interpretation

Explicit `xybFromSRGB` encoding now reads padded RGB8 or opted-in normalised RGB Float32 directly. The public API validates the predecessor's actual sequential 4:4:4 profile, table and restart restrictions. It rejects arbitrary source ICC profiles. The XYB inverse writes into final RGB storage at scales 1/2/4/8 and attaches a matching sRGB profile; it does not carry the encoded XYB profile onto already-converted RGB samples. Inspection keeps the original component/profile interpretation. Separate sample and colour conversion fields report quantisation and colour transforms.

The unchanged ICC `sRGB2014.icc` bytes (3024 bytes, SHA-256 `384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a`) are embedded under the ICC's profile licence, with copyright retained. The provenance verifier checks the original fixture, embedded array and notice. This static profile is metadata, not a runtime CMS dependency.

Executed evidence:

- Linux ARM64 / Swift 6.4: **308 tests in 38 suites passed**, including XYB native/public byte identity, 8/32-bit source storage, odd/one-pixel widths, both decode storage shapes, all scales, source padding, ICC replacement and malformed/unknown colour interpretation rejection.
- Local macOS ARM64 / Swift 6.4: the same matrix passed on scalar and Accelerate. ASan and TSan executable harnesses exited 0. All 71 predecessor identity records still match byte-for-byte.
- The embedded output profile agrees with system sRGB on 216 RGB grid points within one sample unit via CoreGraphics/ColourSync. The retained XYB ICC inverse comparison now requires all 256 conversions to occur; a missing conversion is a failure, not a silent skip. These are colour interpretation checks, not a broad independent JPEG corpus qualification.
- The independent public consumer passed XYB encoding/inspection/decoding and both conversion reports.
- At preceding commit `371d59d`, CI [37651331367](https://github.com/raster-labs/SwiftJLI/actions/runs/37651331367) passed **all eight jobs**, including macOS debug/release, ASan/TSan and all **nine Apple SDK compilation targets**, including watchOS arm64_32. Each used SDK 26.5 / Apple Swift 6.3.3 / Xcode 26.6, with deployment target 26.0. This closes the stride-type compile failure. Runtime/device acceptance and fresh XYB-head CI remain separate gates.

## Normalised Float32 colour output and fuzz runner

The explicit `.float32NormalisedSRGB` decoder profile exposes fractional XYB reconstruction before integer rounding, divided by 255 into [0,1], with the matching sRGB profile. `sampleConversion` reports `.rawSRGBToNormalisedFloat32`. This deliberately differs from the predecessor's raw 0–255 Float32 buffer; the migration guide makes the range change explicit. Ordinary greyscale raw floats retain their existing units, and the normalised sRGB option rejects JPEGs without the recognised XYB interpretation.

- Linux ARM64 / Swift 6.4: **310 tests in 39 suites passed**. Tests match the native fractional inverse/255 bit-for-bit at all scales, prove fractional values survive, and verify allocating/padded caller storage, reports and profile restrictions.
- Local macOS ARM64 / Swift 6.4: the same matrix passed scalar/Accelerate, plus ASan and TSan executable harnesses (exit 0). The 71 predecessor identity records remain unchanged.
- CI [37653546500](https://github.com/raster-labs/SwiftJLI/actions/runs/37653546500) passed all eight jobs at the preceding integer-XYB commit `016dc54`, including full macOS release/ASan/TSan and the nine Apple SDK targets. The normalised-output commit requires its own CI run.
- `Examples/DecoderFuzz` generates 90 profile/scale seeds across predictive, bounded-error, sequential/progressive DCT and XYB integer/Float32 output. Deterministic mutations target truncation, entropy bytes, marker lengths, insertion/deletion and runs of bytes. Valid seeds continue to exercise final reconstruction.
- `Scripts/run-decoder-fuzz.py` builds a release executable and supervises three independent entry campaigns, each with a one-hour default, one CPU, a 256 MiB container ceiling, explicit operation budgets and a 30-second heartbeat watchdog. It records source/binary hashes, compiler/container identity, exit codes, outcomes and process peak RSS. This is deterministic mutation fuzzing without coverage guidance; process RSS is not allocator/copy telemetry.
- A three-second supervisor smoke run passed: inspect 638253 attempts, allocating decode 72090, caller-destination decode 67752; both accepted and rejected inputs occurred. Peak process RSS was approximately 23–25 MiB. These short runs do not meet the one-hour acceptance requirement. Long campaigns must complete successfully before that gate is claimed.
- Injecting a container termination made the supervisor exit 1 and mark the campaign failed, cleaning up the other two workers. Replaying allocating-decode attempt 100 twice produced identical candidate bytes (SHA-256 `05ecd1b678d6d9da75a6629c2bb575d10be1944620ba6363dc31e77248343719`).

Reproduce (requires Docker with the chosen Swift image already available):

```sh
python3 Scripts/run-decoder-fuzz.py --output-dir /tmp/swiftjli-fuzz-campaign
```

A failed compressed candidate is retained when an unexpected Swift error is caught. For a native crash/hang, the last progress count bounds the deterministic sequence position. Run the logged binary/entry with an optional final replay-attempt integer to save that candidate before execution; preceding candidates are regenerated from the fixed seed. Do not treat an interrupted or watchdog-terminated campaign as a pass.

## Independent decoder heap measurements

The Linux/glibc [allocation experiment](../../Examples/AllocationProbe/README.md) interposes actual allocator calls in an independent public consumer. It builds release without sanitizers and leaves the shipping codec unchanged. [Retained results](Allocations/results.json) pin the codec at `aa2abdd` (same source as `1072de4`), the new experiment's exact file hashes, Swift 6.4, the immutable ARM64 container and the binary. The recorded worktree contains the then-uncommitted experiment; this is not a clean-checkout claim. Raw histograms and compiler/build/run logs are retained alongside the results.

All **60 baseline measurements and 60 deliberate-copy controls passed**, covering 257×257 and 1024×1024 predictive UInt16, DCT UInt12, RGB8, XYB RGB8 and normalised XYB Float32. Three warmed repetitions cover each allocating/caller-destination path. Every sample and interpretation matched, caller allocation identity remained unchanged and zero-filled row padding remained intact. C calibration checks allocation/free accounting; a separate Swift owned-storage calibration verifies that Swift image allocation reaches the interposer. The measured Swift array allocation header was 32 bytes.

Allocating decode showed one final-frame-size allocation; caller-destination decode showed none at either its packed logical size or padded capacity. Deliberately copying the decoded frame inside the measured scope added one corresponding allocation in all 60 controls, even while output identity remained unchanged. Supplying baseline records as the positive control made the verifier fail as expected. These checks supplement the existing sample, padding, source-path and mutation evidence rather than relying on the codec's own allocation report.

Median peak **new requested heap bytes during decode**, over three repetitions at 1024×1024:

| Profile | Allocating decode | Preallocated caller destination |
| --- | ---: | ---: |
| Predictive UInt16 | 7,457,179 | 5,359,639 |
| DCT UInt12 | 19,703,523 | 17,605,983 |
| RGB8 | 33,414,574 | 30,268,458 |
| XYB RGB8 | 38,027,290 | 34,881,174 |
| XYB normalised Float32 | 47,464,474 | 34,881,174 |

Sources, compressed input, references and caller destinations were allocated before measurement. Thus the last column excludes the caller's existing image memory; it must not be presented as total application peak or as eliminating the necessary final image. Runtime, parser and algorithm allocations within the window are included. Allocator overhead, pre-existing allocations, direct mmap, stack storage and transient allocator-internal realloc copies are excluded. No timing result is taken from the instrumented build. The probe does not intercept all copy instructions; it detects the tested full-frame array-copy shape. Pure workspace attribution, encoding, failure/cancellation accounting, cross-codec paths and other platforms remain open. Public `peakWorkspaceBytes` remains nil.

Reproduce with `python3 Scripts/run-allocation-probe.py --output-dir /tmp/swiftjli-allocation-probe`. The runner rejects nonzero exits, missing profiles, overflows and unexpected frame allocations, and retains failed evidence rather than accepting partial output. Production codec files still match the active fuzz campaign's source hashes.

## Public-profile audit, remote consumer and benchmark preparation

[PROFILE_AUDIT.md](PROFILE_AUDIT.md) now accounts for all 16 predecessor encoder fields, decoder controls, image/colour labels and native inspection information. A public comparison executable at predecessor `0a4ded0` and successor `197b209` passed five targeted checks on macOS ARM64 / Apple Swift 6.4. It confirms functioning predecessor RGBA8 alpha-discard, preconverted YCbCr8 and RGB8-to-greyscale profiles have no equivalent public successor option yet. Direct signed input is also rejected: the predecessor preserves signed-labelled UInt16 bytes in exact SOF3 but loses its signed flag on decode, contrary to its comment. Its output-colour override can merely relabel RGB bytes. Those unsafe interpretation behaviours must not be silently restored. Progressive/chroma inspection fields and the narrower distance range are also explicit open items. [Raw observations, harness and source hashes](ProfileAudit/results.json) are retained; this is an inventory with concrete remaining work, not a parity pass.

A fresh consumer resolved `https://github.com/raster-labs/SwiftJLI.git` at `197b20913473855d8828a82a50891ce6f2fae504`, built and passed predictive, progressive, float and XYB public calls (exit 0). Its [manifest, remote lockfile, log and hashes](RemoteConsumer/results.json) are retained. This verifies clean remote revision consumption, not consumption of a stable semantic-version tag or an application cutover.

CI [37656560684](https://github.com/raster-labs/SwiftJLI/actions/runs/37656560684) passed all eight jobs at `aa2abdd`, which includes normalised Float32 XYB output. This covers the full macOS debug/release/ASan/TSan suite, the four Linux Swift 6.2/6.4 architecture jobs, independent consumer, common contract identity and nine Apple SDK compilation targets. It still does not replace native Intel macOS or Apple device/simulator runtime qualification.

The [expanded performance harness](Benchmarks/Expanded/README.md) now checks exact old/new codestreams and decoded samples over predictive UInt16, DCT UInt12, sequential/progressive RGB8 and XYB RGB8. A fresh macOS release build exited 0, followed by all five smoke cases. `-Xswiftc -gnone` avoids the observed local release link-driver stall without changing shipping package flags. Full five-warm-up/twenty-iteration runs at 512 and 1024 remain pending until competing fuzz/build work is finished. Smoke timings are not acceptance results. An unmodified-predecessor Linux comparison build failed on its unconditional CryptoKit import; no Linux baseline result is claimed.

## Specialised JPEG inspection

`Decoder.inspectJPEG(_:options:)` now closes the native inspection-information gap without changing the common operation's call shape. It provides encoded coding process, sampling classification and exact factors, progressive/precision/XYB flags, scan count, restart interval and predictive settings, alongside common `ImageInfo`. It reuses the same bounded parser and does not decode pixels. A nonzero predictive point transform is explicitly distinguished from exact reconstruction. Known XYB is detected from validated interpretation, correcting the predecessor inspector's hard-coded false flag.

- Linux ARM64 / Swift 6.4: **315 tests in 40 suites passed**, including the new feature matrix and 4:4:0 structural-inspection case. All 18 8/12-bit sampling/scan combinations preserve encoded geometry despite reduced/Float32 output configuration.
- Local macOS ARM64 / Swift 6.4: the independent public consumer built and passed the new extension call as well as its existing codec matrices (exit 0).
- All four public inspection/decode entries passed a three-second deterministic mutation smoke: common inspect 680320 attempts, JPEG-specific inspect 650779, allocating decode 116852, caller-destination decode 85097. These are smoke results, not one-hour qualification.
- The supervisor now executes a per-campaign binary copy and verifies that sources did not change during its build. A separate build cache leaves the earlier running `.build-fuzz` executable intact. The existing long campaign remains pinned to `1072de4`; it does not qualify this new entry point or later source revisions.
- CI [37658940472](https://github.com/raster-labs/SwiftJLI/actions/runs/37658940472) passed all eight jobs at preceding `197b209`, including the committed allocation experiment/documentation checkpoint. Fresh inspection-head CI remains required.

Signed standalone input remains rejected under COMMON_API API-06: the predecessor preserved bytes but lost signed provenance. No private JPEG marker or implicit signed-to-unsigned mapping is introduced. The guide records this required disposition; an external signed-metadata contract is separate work.

## Full finite distance range

The adapter now accepts every finite nonnegative distance, closing its artificial upper bound of 25. Perceptual YCbCr/XYB table construction saturates to 1–255 in floating point before integer conversion, so a finite distance whose intermediate scale overflows cannot trap. Quantisation behaviour for representable values is unchanged; NaN, infinities and negative distances still fail public configuration validation.

- Linux ARM64 / Swift 6.4: **318 tests in 41 suites passed**, including sequential/progressive, greyscale/RGB, XYB and jpegli-AQ cases at distances 26, 1000 and the largest finite Double, plus saturated-table and rejection checks.
- A macOS public consumer compared 14 cases at distances 26/1000 against the actual pinned predecessor: every codestream and decoded sample byte matched. Seven further 8/12-bit and colour/profile cases encoded and decoded at the largest finite Double without invoking the unsafe predecessor path. [Source hashes, harness and observations](DistanceRange/results.json) are retained; the record explicitly includes uncommitted source hashes.
- The macOS native identity executable passed, and `cmp` against the executed predecessor identity file exited 0 for all 71 records. The inspection/distance changes still require their final head CI and final fuzz qualification.

## Completed one-hour checkpoint fuzz campaigns

The three campaigns launched against **`1072de44ee31e626886efb5cb9e37215648c3db8`** each completed at least 3600 seconds and exited 0. The supervisor exited 0. The on-disk executable still matches its recorded SHA-256, and every recorded source hash was checked against that exact Git revision after completion. [Manifest and compressed raw logs](Fuzz/1072de4/campaign.json) are retained, with archive and uncompressed hashes.

| Entry | Attempts | Accepted | Rejected | Peak process RSS bytes |
| --- | ---: | ---: | ---: | ---: |
| Common inspection | 745,166,768 | 275,254,304 | 469,912,464 | 24,117,248 |
| Allocating decode | 83,473,135 | 21,455,539 | 62,017,596 | 26,243,072 |
| Caller-destination decode | 78,344,826 | 20,119,894 | 58,224,932 | 25,944,064 |

No unexpected error, crash or watchdog failure was observed. This is deterministic mutation fuzzing, not coverage-guided security certification. The accepted inspection count does not certify entropy validity. RSS is process memory, not allocator/copy accounting. These results qualify that checkpoint only: the later JPEG-specific inspection entry and subsequent changes require their own final campaigns. The original build cache was left intact while the later smoke used a separate cache and copied executable.

## Remaining migration requirements

- Resolve the remaining profile gaps in PROFILE_AUDIT.md and qualify broader ICC/interoperability coverage. Specialised inspection and finite distance range are now implemented; RGBA, preconverted YCbCr and RGB-to-greyscale remain open. Unsupported combinations remain explicit errors.
- Qualify public DCT backend performance and resource instrumentation. Backend selection and direct storage are now implemented; full platform qualification remains open.
- Complete public-mode coverage of the retained regression corpus as lossy integration lands. All predecessor test files are now represented; the six duplicate contract files and predecessor module/version overview are explicitly retired in provenance.
- Complete parser/entropy security review, mutation/resource/cancellation tests, fuzzing, sanitizers and native platform/SDK coverage.
- Extend the measured Linux decoder allocation evidence to encoding, failure/cancellation, workspace attribution and other platforms; qualify controlled release performance against the pinned predecessor and the shared-storage cross-codec extension.
- Finish documentation, release/versioned consumption and the full acceptance audit. Fresh remote revision consumption is now executed; a stable version tag has not been created or qualified. CLI payload verbs remain separately budgeted new work under IMPLEMENTATION.md I3; diagnostic capabilities already read the real library values.

No predecessor release, consumer cutover, archive, stable successor tag or merge has been performed by this checkpoint.
