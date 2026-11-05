# djpeg performance work — 2 November 2026

**SwiftJLI beats djpeg on two tested large lossless ramp cases, but does not beat it across the matrix.** With both SwiftJLI revisions rebuilt using the same Swift 6.4.2 toolchain, 2048² ramp decoding is 11.7% faster than djpeg and 3072² ramp decoding is 22.5% faster. Both wins exceed 5% in both rounds. The original 2048² mixed case improves from 130.472 ms to 31.399 ms (4.16× throughput at fixed image size), but remains 16.3% slower than djpeg. Its peak RSS falls from 46.22 MiB to 30.27 MiB, a 34.5% reduction; djpeg still uses less memory.

Baseline source: `d25d4567c7932a0b3fd181901d16ce35a9eded29`. Candidate source: `d1cd30ace21e9317402b54918b3fef55d880c4d5` on `codex/djpeg-performance`, pinned by [the source manifest](audit-source-manifest.json). Suite policy **0.10.0**; Swift 6.2 manifest minimum; Apple OS 26.0 floor. This is maintenance of the existing codec/CLI, without public API, precision, fidelity, executor-policy or library resource-limit changes. No external codec is called by the implementation.

## Implemented changes

- Greyscale SOF3 decoding writes into its existing final destination and keeps one row of `Int32` predictor history. Scratch changes from `4 × width × height` to `4 × width` bytes: **16 MiB → 8 KiB at 2048²**. All seven predictors, point transforms, restart handling and row cancellation checks are retained. RGB and native owned-output paths retain their full-plane implementation.
- A short Huffman category and its already-buffered magnitude are decoded together. Categories 0/16 retain their special behaviour; long codes, insufficient bits, markers, truncation and invalid categories use the existing checked path.
- CLI decoding avoids a duplicate inspection pass unless `--json` needs the coding-process report.
- PNM output uses bounded row batches, normally at most **64 KiB**, or one wider row. Packed 16-bit output swaps adjacent bytes in unaligned UInt64 words, with a scalar tail. Atomic regular-file publication, synchronous borrows, non-blocking stdout, size admission and deadlines remain intact. NRRD serialisation is unchanged.

## Method and toolchain

The initial session reported Swift 6.4.0 / Xcode 27.1, while a later environment query reported Swift 6.4.2 / Xcode 27.2. Earlier comparisons therefore mix compiler versions and are retained only as exploratory evidence. **All final tables below use fresh baseline and candidate builds with Swift 6.4.2** (`swiftlang-6.4.2.1.9`, Xcode 27.2 `27B52`). [Compiler hashes](compiler-pin.json), [host details](environment.json) and [native compile/link commands](swiftjli-native642-matrix-results.json) are archived. The original compiler transition and an initial native-harness SDK mismatch were resolved before final measurements.

Host: Mac16,5, 16 logical processors, 64 GiB RAM, macOS 27.0.1 (`26A434`), AC power. This is a working machine with competing user workloads; results are advisory local evidence, not a dedicated-hardware release qualification. No benchmark overlapped our builds, profilers, sanitiser runs or other codec benchmarks. Native measurements reported nominal thermal state throughout.

The [CLI runner](../../../../Scripts/benchmark-djpeg.py) uses the same JPEG bytes, five warmups and twenty timed fresh processes per implementation per case, in two rounds. Tool order rotates and reverses. Timings include process launch, `/usr/bin/time -l`, file input, decoding and PNM output to `/dev/null`; peak RSS comes from that child process. These timings do not isolate codec kernels. djpeg is libjpeg-turbo **3.2.0**, with its installed defaults; 12-bit DCT explicitly uses `-precision 12`. SwiftJLI uses unchanged automatic backend/worker defaults.

Before timing, the runner requires candidate/baseline layout and sample identity and records complete PNM hashes; complete PNM bytes also matched in every final validation. Lossless comparison to djpeg requires exact samples. DCT gates remain maximum error 2 for 8-bit and 4 for 12-bit. PNM parsing preserves whitespace-valued initial pixels. Timeouts terminate the child process group and retain failure details.

## CLI results

Values below are the arithmetic mean of the two round medians. Percentages compare those values; a negative difference from djpeg means SwiftJLI is faster. Individual samples, per-round median/p95/min/max, throughput, RSS, commands and input/output/binary hashes are retained in the linked JSON reports. [Computed summary](summary.json).

### Original comparison

| Input | Before ms | Updated ms | djpeg ms | Updated versus djpeg | Updated RSS MiB |
|---|---:|---:|---:|---:|---:|
| lossless16 512² | 16.660 | 10.374 | 7.193 | +44.2% | 8.36 |
| lossless16 2048² | 130.472 | 31.399 | 27.009 | +16.3% | 30.27 |
| dct12 512² | 18.463 | 12.329 | 7.398 | +66.6% | 12.42 |

[Final original raw results](cli-comparison-swift642.json): three accepted cases in each round. Lossless outputs match exactly; DCT12 differs by at most one sample unit. Sequential and progressive RGB512 remain excluded: their maximum difference is 3 against the unchanged 2-unit gate. Their candidate/baseline bytes still match. XYB is not included because the ordinary djpeg colour interpretation is not equivalent.

### Expanded lossless corpus

| Pattern / size | Before ms | Updated ms | djpeg ms | Updated versus djpeg | Updated RSS MiB |
|---|---:|---:|---:|---:|---:|
| flat 19² | 9.118 | 9.072 | 6.094 | +48.9% | 7.06 |
| flat 512² | 16.492 | 10.023 | 7.141 | +40.4% | 7.75 |
| flat 2048² | 118.931 | 19.382 | 17.608 | +10.1% | 16.68 |
| flat 3072² | 254.938 | 31.238 | 31.513 | -0.9% | 28.55 |
| ramp 19² | 9.657 | 9.675 | 6.625 | +46.0% | 7.06 |
| ramp 512² | 17.158 | 10.717 | 8.012 | +33.8% | 8.35 |
| ramp 2048² | 126.825 | 23.596 | 26.710 | -11.7% | 26.01 |
| ramp 3072² | 269.774 | 38.243 | 49.364 | -22.5% | 43.88 |
| noise 19² | 9.885 | 9.844 | 6.808 | +44.6% | 7.06 |
| noise 512² | 18.967 | 12.774 | 8.542 | +49.5% | 8.70 |
| mixed 19² | 9.740 | 9.740 | 6.649 | +46.5% | 7.04 |
| mixed 512² | 17.816 | 11.543 | 8.304 | +39.0% | 8.41 |
| mixed 2048² | 131.378 | 32.340 | 27.924 | +15.8% | 30.28 |

[Final expanded raw results](cli-pattern-comparison-swift642.json): thirteen accepted cases per round, all with exact samples. **Only ramp2048 and ramp3072 are more than 5% faster than djpeg in both rounds.** Flat3072 changes direction between rounds and is not a repeatable win. Small cases are dominated by process startup.

Noise2048, noise3072 and mixed3072 are explicitly excluded: both SwiftJLI builds return resource-limit exit 5 under the unchanged **512 MiB workspace ceiling**. The CLI does not expose a way to raise that ceiling independently. These are admission exclusions, not codec corruption or successful performance results. The [initial aborted attempt](cli-pattern-initial-resource-failure.json) is retained; the runner now records matching rejections without accepting timings. No limit or quality threshold was relaxed.

## Public-library results

The separate [matched-toolchain native matrix](swiftjli-native642-matrix-results.json) measures allocated-output `SwiftJLI.Decoder.decode`, excluding file reads, output checking, PNM conversion and process startup. It compares SwiftJLI revisions only, **not an in-process libjpeg-turbo API**. Five warmups and twenty timed calls cover all sixteen cases, twice, with binary order reversed. All decoded bytes match the generated source. Both revisions explicitly use 8 GiB workspace / 10 GiB total-memory admission limits, allowing cases excluded by CLI defaults.

| Pattern / size | Before ms | Updated ms | Latency reduction |
|---|---:|---:|---:|
| flat-19 | 0.0110 | 0.0084 | 23.9% |
| flat-512 | 0.7645 | 0.5373 | 29.7% |
| flat-2048 | 11.1332 | 8.1685 | 26.6% |
| flat-3072 | 24.7131 | 18.0860 | 26.8% |
| ramp-19 | 0.0097 | 0.0082 | 15.4% |
| ramp-512 | 1.0758 | 0.7208 | 33.0% |
| ramp-2048 | 16.4731 | 10.8989 | 33.8% |
| ramp-3072 | 36.5644 | 23.1589 | 36.7% |
| noise-19 | 0.0101 | 0.0082 | 18.1% |
| noise-512 | 2.5450 | 2.3676 | 7.0% |
| noise-2048 | 38.2644 | 37.8750 | 1.0% |
| noise-3072 | 86.5056 | 86.0427 | 0.5% |
| mixed-19 | 0.0097 | 0.0077 | 20.4% |
| mixed-512 | 1.7041 | 1.3139 | 22.9% |
| mixed-2048 | 21.9419 | 19.5434 | 10.9% |
| mixed-3072 | 48.2201 | 43.6029 | 9.6% |

Fourteen cases improve by more than 5% in both rounds. The two large noisy cases are approximately unchanged; no case regresses by more than 5% in both rounds. The earlier fused-path and store-specialisation experiments are diagnostic only. The store specialisation was discarded because its small mixed-image gain coincided with slower flat-image decoding. The final code does not contain it.

## Validation and memory semantics

| Check | Command / evidence | Outcome |
|---|---|---|
| Fresh Swift6.4.2 release suite | `swift test -c release --jobs 4 --scratch-path /private/tmp/swiftjli-djpeg642-candidate-build`; [log](macos-swift642-release-test.log) | Exit 0; **364 tests / 52 suites** |
| Final release CLI | `python3 Scripts/test-cli.py --binary /private/tmp/swiftjli-djpeg642-candidate-build/out/Products/Release/swiftjli-cli --output /private/tmp/swiftjli-djpeg642-final-cli-checks`; [report](final-cli-report.json) | Exit 0; **237 process checks** |
| AddressSanitizer full suite | `swift test --jobs 4 --scratch-path /private/tmp/swiftjli-djpeg642-asan --sanitize address`; [log](asan-test.log) | Exit 0; **364 tests / 52 suites**, no sanitizer finding |
| ThreadSanitizer focused suite | `swift test --jobs 4 --scratch-path /private/tmp/swiftjli-djpeg642-tsan --sanitize thread --filter "LosslessRowStorageTests\|LosslessDifferenceTests\|NativeExecutionTests\|OwnershipTests\|CancellationPublicationTests"`; [log](tsan-test.log) | Exit 0; **22 tests / 3 suites**, no sanitizer finding |
| Independent lossless interoperability | `python3 Scripts/verify-lossless-interop.py --output-dir /private/tmp/swiftjli-djpeg642-final-oracle --scratch-path /private/tmp/swiftjli-djpeg642-final-oracle-build`; [log](final-lossless-interop.log) | Exit 0; **210 Swift encode→djpeg and 210 cjpeg→Swift decode cases** |
| ASan CLI integration | [log](asan-cli-tests.log) | Exit 0; **237 process checks**, no sanitizer finding |

New [row-storage tests](../../../../Tests/SwiftJLITests/Native/LosslessRowStorageTests.swift) cover predictors, precision, point transforms, restart segments, width/height one, offset/odd-stride storage, padding sentinels, independent cjpeg fixtures, truncation and deadlines. [Entropy tests](../../../../Tests/SwiftJLITests/Native/LosslessDifferenceTests.swift) compare every magnitude at every bit offset with bitwise decoding, including long codes, markers and invalid categories. [CLI checks](../../../../Scripts/test-cli.py) cover exact bytes, JSON/plain equivalence, batch boundaries, wide rows, file/stdout equivalence and stalled-output deadlines.

The predictor buffer is freed with `defer`, including failures. Caller storage and CLI scratch remain synchronously borrowed; no pointer escapes. Word conversion uses unaligned loads and SE-0349 raw-byte stores, restricted to complete words inside a validated row, followed by the 0–6-byte tail. A standalone ASan checker also passed 16,448 offset/length/guard-byte cases. Existing destination identity, copy-report, cancellation and resource assertions pass.

The library still allocates the final decoded image (or fills supplied storage without an extra hand-off image). CLI conversion still reads and writes every output sample. Process RSS includes runtime, compressed buffers, allocator retention and destination pixels; it is not pure workspace. `peakWorkspaceBytes` remains unknown rather than a fabricated measurement. The theoretical predictor/scratch reductions and measured process RSS describe different quantities. No new allocator-instrumentation or zero-copy shell-output claim is made.

## Reproduction, provenance and remaining limits

Build isolated baseline and candidate checkouts with the identical pinned compiler. Final baseline command: `swift build -c release --jobs 4 --scratch-path /private/tmp/swiftjli-djpeg642-baseline-build --product swiftjli-cli`. The candidate test build uses the same release configuration. Check [compiler hashes](compiler-pin.json) and [the source/evidence manifest](audit-source-manifest.json). The final raw CLI JSON embeds every command and argument. The [native record](swiftjli-native642-matrix-results.json) embeds exact compile/link/run commands, SDK paths and object/binary hashes.

```sh
python3 Scripts/benchmark-djpeg.py --baseline /path/to/baseline/swiftjli-cli --candidate /path/to/candidate/swiftjli-cli --djpeg /path/to/djpeg --fixtures /path/to/original-fixtures --output original.json
python3 Scripts/benchmark-djpeg.py --matrix lossless-patterns --baseline /path/to/baseline/swiftjli-cli --candidate /path/to/candidate/swiftjli-cli --djpeg /path/to/djpeg --fixtures /path/to/pattern-fixtures --output patterns.json
```

All inputs are synthetic. [The pattern generator](swiftjli-native-matrix.swift) retains the deterministic seed/formulae and has `generate` and `benchmark` modes. [The original fixture harness](original-fixture-harness.swift) and [its package](original-fixture-Package.swift) retain the original mixed/DCT/RGB generation logic: the predecessor `prepare` mode writes each requested JPEG. Its JLISwift dependency is pinned at `b6df774a3c3ecdf4b98971f31543fdd18074ace2` (v0.6.0); that is fixture provenance, not the speed baseline in this report. Replace recorded local paths with equivalent checkouts when reproducing and verify fixture hashes. Existing independent fixture provenance remains beside [LosslessTests](../../../../Tests/SwiftJLITests/Native/LosslessTests.swift) and [LosslessRestartTests](../../../../Tests/SwiftJLITests/Native/LosslessRestartTests.swift). No patient data or newly relicensed third-party source was introduced.

The original `iteration-*`, unqualified `cli-comparison.json`/`cli-pattern-comparison.json`, and earlier native records remain exploratory. Final performance evidence is identified by the `swift642`/`native642` filenames and manifest. Host/compiler drift, the resolved SDK mismatch, and rejected resource cases are not silently counted as successful runs.

This task does not newly qualify Swift6.2, Linux, Apple simulators or physical Apple devices; the broader [acceptance ledger](../../ACCEPTANCE.md) and stable-release gates remain in effect. The improvements are ready for review, with a limited comparative result: **two repeatable djpeg speed wins, substantial improvement over the old SwiftJLI CLI, and remaining djpeg latency/memory advantages elsewhere.**
