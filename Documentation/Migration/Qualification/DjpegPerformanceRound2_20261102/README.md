# JPEG optimisation follow-up — 2 November 2026

**SwiftJLI improves further, but the goal of beating djpeg across the suite is not achieved.** It is more than 5% faster in both rounds on four large lossless cases against libjpeg-turbo **3.2.1**, and on two large ramp cases against the exact **3.2.0** binary from the previous report. Small CLI decodes and the original mixed 2048² and DCT12 cases still favour djpeg. Decoded samples remain identical to the previous SwiftJLI build throughout the tested corpus.

The comparison baseline is `7f8c1499126c157871a309ffd519a6dc7b6e0c72`, the previous optimisation checkpoint. Benchmarked production source is `b31999bd4246507fc9c7f18cd770b411faea501d`; final test source is `7fe1c7394c3238441b2ef0f068698e766914cebe`. Only two additional regression tests separate those revisions. [Source hashes](source-manifest.json) verify identical production files, and [binary checks](benchmark-binary-recheck.json) verify that the release executable and library object remained byte-identical after the final tests. Suite policy is **0.10.0**, with the existing Swift 6.2 manifest minimum and Apple OS 26.0 deployment floor.

## Changes and fidelity

- Sequential DCT entropy decoding writes directly into a scoped coefficient-plane borrow. A 13-bit lookup combines short AC symbols and magnitudes; EOB/ZRL-only tables retain the cheaper scalar path. IDCT, quantisation and sample rounding retain their existing arithmetic.
- Selected greyscale lossless scans use a bounded 32 KiB combined category/value table. Selection uses scan size, canonical prefix coverage and category diversity. The scalar kernel is retained; a measured `@inline(never)` boundary prevents the added kernel from slowing scalar caller specialisation.
- The CLI uses package-only synchronous adapters with explicit signal/deadline checks propagated into every joined worker. Public asynchronous APIs retain their executor policy. Diagnostics are lazy, elapsed timing reuses the monotonic clock, and common filename extensions avoid Foundation URL construction.
- Ordinary JPEGs without ICC data avoid constructing the XYB profile. Its existing portable identifier implementation replaces the CryptoKit dependency; the complete 728-byte profile and identifier match the frozen predecessor digest.

Precision, signedness, metadata interpretation, copy/fidelity policies and resource limits retain their existing semantics. The implementation never calls djpeg or another external codec. CLI execution and memory accounting are documented in [CLI.md](../../../../CLI.md).

## Method and environment

Both Swift revisions were freshly built with the same Apple **Swift 6.4.2**, Xcode **27.2**, release configuration and four build jobs. Host: **M4 Max, 16 cores, 64 GiB**, macOS **27.0.1**, AC power. Compiler and executable hashes were verified before and after the runs: [initial pin](initial-toolchain.json), [final pin](final-toolchain.json), [3.2.0 comparator pin](djpeg320-pin.json), [host record](environment.json). The installed default changed from djpeg 3.2.0 to 3.2.1 between reports, so both versions are shown explicitly.

CLI timings include process launch, input reading, decoding and PNM output to `/dev/null`, with Darwin `/usr/bin/time -l` measuring peak RSS. Each case has **5 warmups, 20 measured samples and 2 rounds**; tool order rotates and reverses. Tables show the mean of the two round medians. A highlighted win requires **more than 5% lower latency in each round**. Raw results also contain p95, individual samples, throughput, RSS, fixture/output hashes and every argument. No benchmark ran concurrently with our builds, profilers or test suites. These remain advisory measurements from one working host.

The original corpus covers 16-bit lossless at 512²/2048², DCT12 at 512², and sequential/progressive RGB8 at 512². The expanded corpus covers flat/ramp/noise/mixed lossless data at 19²/512²/2048²/3072². The original lossless fixtures are byte-identical to the corresponding mixed fixtures, so their rows are aliases, not additional independent wins.

## CLI comparison: djpeg 3.2.1

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift faster than djpeg | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 10.170 | 9.100 | 7.138 | -27.5% | 7.78 | 2.81 |
| lossless16 2048² | 32.438 | 28.747 | 27.310 | -5.3% | 29.69 | 2.84 |
| dct12 512² | 12.545 | 11.025 | 7.621 | -44.7% | 11.89 | 2.20 |
| flat 19² | 8.731 | 7.887 | 6.092 | -29.5% | 6.47 | 2.75 |
| flat 512² | 9.626 | 8.668 | 6.915 | -25.4% | 7.09 | 2.81 |
| flat 2048² | 19.440 | 18.594 | 20.494 | +9.3% **win** | 16.00 | 2.84 |
| flat 3072² | 31.144 | 29.931 | 36.693 | +18.4% **win** | 27.88 | 2.84 |
| ramp 19² | 9.199 | 8.320 | 6.725 | -23.7% | 6.47 | 2.75 |
| ramp 512² | 10.122 | 9.165 | 7.672 | -19.5% | 7.73 | 2.81 |
| ramp 2048² | 23.230 | 22.157 | 25.821 | +14.2% **win** | 25.42 | 2.84 |
| ramp 3072² | 38.524 | 37.525 | 47.182 | +20.5% **win** | 43.30 | 2.84 |
| noise 19² | 9.590 | 8.555 | 6.819 | -25.5% | 6.47 | 2.75 |
| noise 512² | 12.016 | 11.140 | 8.199 | -35.9% | 7.97 | 2.81 |
| mixed 19² | 9.230 | 8.397 | 6.600 | -27.2% | 6.47 | 2.75 |
| mixed 512² | 10.678 | 9.767 | 7.919 | -23.3% | 7.78 | 2.81 |
| mixed 2048² | 32.140 | 28.729 | 27.656 | -3.9% | 29.69 | 2.84 |

Four repeatable wins: **flat2048 9.3%, flat3072 18.4%, ramp2048 14.2%, ramp3072 20.5%**. Original mixed2048 improves **32.438 → 28.747 ms (11.4%)**, but remains **5.3% slower** than djpeg. Its median peak RSS is approximately **29.69 MiB**, versus approximately **2.84 MiB** for djpeg; this round does not establish a memory win. The previous checkpoint had already removed the full predictor plane and full-image PNM serialisation buffer.

[Original raw measurements](cli-original.json) · [Pattern raw measurements](cli-patterns.json)

## CLI comparison: original djpeg 3.2.0

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift faster than djpeg | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 9.095 | 8.194 | 6.362 | -28.8% | 7.78 | 2.81 |
| lossless16 2048² | 30.706 | 27.124 | 26.063 | -4.1% | 29.69 | 2.84 |
| dct12 512² | 11.139 | 9.789 | 6.560 | -49.2% | 11.89 | 2.20 |
| flat 19² | 7.872 | 6.997 | 5.237 | -33.6% | 6.47 | 2.73 |
| flat 512² | 8.663 | 7.867 | 6.004 | -31.0% | 7.09 | 2.81 |
| flat 2048² | 18.107 | 17.218 | 16.556 | -4.0% | 16.00 | 2.84 |
| flat 3072² | 30.014 | 29.063 | 29.092 | +0.1% | 27.88 | 2.84 |
| ramp 19² | 8.430 | 7.524 | 5.781 | -30.2% | 6.47 | 2.73 |
| ramp 512² | 9.447 | 8.740 | 7.109 | -22.9% | 7.73 | 2.81 |
| ramp 2048² | 22.473 | 21.646 | 25.252 | +14.3% **win** | 25.42 | 2.84 |
| ramp 3072² | 37.388 | 36.361 | 48.531 | +25.1% **win** | 43.30 | 2.84 |
| noise 19² | 8.523 | 7.761 | 5.852 | -32.6% | 6.47 | 2.73 |
| noise 512² | 11.272 | 10.559 | 7.541 | -40.0% | 7.97 | 2.81 |
| mixed 19² | 8.706 | 7.706 | 5.881 | -31.0% | 6.47 | 2.73 |
| mixed 512² | 9.989 | 9.052 | 7.195 | -25.8% | 7.78 | 2.81 |
| mixed 2048² | 31.514 | 27.780 | 26.870 | -3.4% | 29.69 | 2.84 |

Only **ramp2048 (14.3%)** and **ramp3072 (25.1%)** exceed 5% in both rounds. Flat3072 changes direction between rounds and is not a repeatable win. Original mixed2048 remains **4.1% slower**. Each version comparison interleaves its own Swift controls; absolute times vary between batches, so differences between these tables are not isolated measurements of the djpeg version change.

[Original raw measurements](cli-original-320.json) · [Pattern raw measurements](cli-patterns-320.json) · [Commands](benchmark-commands-320.json)

## Quality and resource exclusions

All successful Swift baseline/candidate CLI outputs have identical complete PNM bytes and sample values. Lossless comparisons against djpeg require zero sample difference. DCT12 retains the predeclared tolerance of four source sample units; the observed difference is one. RGB8 and progressiveRGB8 retain their tolerance of two; both Swift revisions differ from djpeg by three on those corpus images, so those cases are **excluded from timing acceptance** for both comparator versions. This existing cross-decoder difference was not concealed or relaxed.

Noise2048, noise3072 and mixed3072 are excluded from CLI timings because both Swift revisions return resource-limit exit 5 under the unchanged 512 MiB workspace ceiling. These are explicit admission exclusions, not successful decodes. The separate native matrix raises workspace/total-memory admission to 8/10 GiB for both revisions and checks all sixteen lossless outputs exactly. Benchmark exclusions and commands remain in each raw JSON.

## Public-library measurements

These measure allocated-output `Decoder.decode`, excluding process launch, input reads, verification and PNM output. They compare SwiftJLI revisions, **not an in-process libjpeg-turbo API**. The same 5 warmups/20 samples/two reversed-order rounds apply. All sixteen lossless outputs match synthetic source bytes; all twelve DCT outputs have identical hashes to the prior Swift revision.

| Case | Prior Swift ms | Updated Swift ms | Latency reduction |
|---|---:|---:|---:|
| flat-19 | 0.0082 | 0.0088 | -7.6% |
| flat-512 | 0.5324 | 0.5495 | -3.2% |
| flat-2048 | 8.0119 | 7.9058 | +1.3% |
| flat-3072 | 17.7942 | 17.5699 | +1.3% |
| ramp-19 | 0.0079 | 0.0081 | -2.5% |
| ramp-512 | 0.7055 | 0.7075 | -0.3% |
| ramp-2048 | 10.7700 | 10.9151 | -1.3% |
| ramp-3072 | 22.8231 | 22.9836 | -0.7% |
| noise-19 | 0.0083 | 0.0090 | -8.1% |
| noise-512 | 2.3351 | 2.3522 | -0.7% |
| noise-2048 | 37.1475 | 37.4652 | -0.9% |
| noise-3072 | 83.1745 | 84.0298 | -1.0% |
| mixed-19 | 0.0077 | 0.0080 | -3.5% |
| mixed-512 | 1.2713 | 1.0800 | +15.0% |
| mixed-2048 | 19.3452 | 16.5688 | +14.4% |
| mixed-3072 | 42.8915 | 36.9106 | +13.9% |

Large mixed lossless images improve approximately **14–15%**. Two 19² cases (flat and noise) show repeatable **6–9% regressions, approximately 0.4–0.8 microseconds**; therefore this is not a claim of zero regressions. Other large scalar patterns remain close to their previous times.

| Case | Prior Swift ms | Updated Swift ms | Latency reduction |
|---|---:|---:|---:|
| dct12-512.jpg | 2.7079 | 2.1428 | +20.9% |
| dct12-2048.jpg | 41.1597 | 31.8900 | +22.5% |
| rgb8-512.jpg | 4.0880 | 3.2399 | +20.7% |
| rgb8-2048.jpg | 57.5464 | 43.2599 | +24.8% |
| progressiveRGB8-512.jpg | 4.7015 | 4.4446 | +5.5% |
| progressiveRGB8-2048.jpg | 61.5700 | 59.5316 | +3.3% |
| xyb8-512.jpg | 11.1334 | 9.7899 | +12.1% |
| xyb8-2048.jpg | 168.7108 | 148.6619 | +11.9% |
| flat-8-512.jpg | 0.8503 | 0.8431 | +0.9% |
| flat-12-512.jpg | 0.8403 | 0.8248 | +1.8% |
| noise-8-512.jpg | 2.7762 | 2.0907 | +24.7% |
| noise-12-512.jpg | 3.0907 | 2.4829 | +19.7% |

DCT12 improves **20.9% at 512² and 22.5% at 2048²**; sequential RGB2048 improves **24.8%**. These are whole-change measurements, not isolated attribution to one optimisation. [Lossless raw results](native-lossless.json) · [DCT raw results](native-dct.json) · [Build/run commands](benchmark-commands.json).

## Safety, ownership and validation

| Check | Final outcome |
|---|---|
| Fresh baseline release suite | Exit 0; 364 tests / 52 suites |
| Updated release suite | Exit 0; **378 tests / 57 suites** |
| AddressSanitizer full suite | Exit 0; **378 tests / 57 suites**, no finding |
| Release and ASan CLI | Exit 0; **242 process checks each** |
| Focused ThreadSanitizer | Exit 0; **35 tests / 7 suites**, no finding |
| Independent lossless oracle | Exit 0; **210 cases in each direction**, Swift encode→djpeg and cjpeg→Swift decode |
| Independent DCT oracle | Exit 0; **48 profiles in both directions**, maximum difference 2 within existing 8/12-bit tolerances |
| Common contract hashes | All seven unchanged and verified |

[Exact commands, exit codes and log filenames](validation.json) · [Release CLI report](release-cli-report.json) · [ASan CLI report](asan-cli-report.json). An attempt to reuse an already populated CLI evidence directory was rejected by the test runner before tests ran; it was rerun into fresh directories, with the rejected invocation retained under `Experiments`.

The lossless table lives only for its synchronous scan. At the 16,384-sample threshold its 32 KiB plus the 4×width predictor row fits the existing 8×sample workspace reservation. At most three AC tables occupy 96 KiB within the existing 1 MiB fixed scratch reservation. Tables add no full-image allocation. Every destination/row borrow remains scoped; workers join before owners are released. `peakWorkspaceBytes` remains unknown rather than fabricated, and process RSS is distinct from codec workspace/copy telemetry.

[Lossless tests](../../../../Tests/SwiftJLITests/Native/LosslessLookaheadTests.swift) cover all 327,680 prefix/offset/table combinations, seven predictors, point transforms, restarts, padding and six invalid destination layouts without writes. [AC lookup tests](../../../../Tests/SwiftJLITests/Native/ACLookaheadTests.swift) and [scoped AC tests](../../../../Tests/SwiftJLITests/Native/ScopedACDecoderTests.swift) compare prefixes, run boundaries, malformed/truncated input, restart positions and guard bytes against retained reference paths. [Host adapter tests](../../../../Tests/SwiftJLITests/CLISynchronousExecutionTests.swift) compare bytes/reports and check host/nested-task cancellation with worker joins. [ICC identity](../../../../Tests/SwiftJLITests/Native/ICCProfileIdentityTests.swift) verifies the complete profile digest.

## Reproduction, rejected experiments and limits

The archived runners and harnesses retain exact commands and original scratch paths. Substitute equivalent checkout/build/fixture paths when reproducing. Use [the CLI runner](../../../../Scripts/benchmark-djpeg.py), [native lossless runner](run-native-lossless.py), [native DCT runner](swiftjli-round2-final-dct-benchmark.py), and [validation runner](run-final-validation.py), with a fresh CLI output directory.

All fixtures are synthetic. Original fixture generation is pinned to JLISwift `b6df774a3c3ecdf4b98971f31543fdd18074ace2` in [the earlier report](../DjpegPerformance20261102/README.md); JLISwift itself is not timed in this follow-up. The [lossless generator](swiftjli-native-matrix.swift) retains deterministic patterns. Four extra flat/noise DCT fixtures use the prior SwiftJLI encoder, not cjpeg: [generator](swiftjli-round2-dct-fixture-generator.py), [commands and hashes](swiftjli-round2-dct-fixture-provenance.json). Independent cjpeg/djpeg oracle fixtures are generated separately by the repository verification scripts. No third-party code or fixtures were newly relicensed.

Rejected experiments include SIMD output rounding (slower), generic/shared lossless dispatch (scalar regressions), forced row inlining (no resolution), a 10-bit/4 KiB table (only 1–2% mixed gain), explicit lookup output-store specialisation (no gain), and moving host cancellation into the existing token (approximately 10% ramp regression). The added nested-cancellation test was retained while that production change was discarded. Linker dead-stripping changed neither dependencies nor speed. [Experiment records](Experiments/swiftjli-round2-lossless-experiment-manifest.json) and adjacent raw summaries preserve these decisions. No rejected production experiment is in the final source.

This round qualifies the stated local macOS toolchain only. Swift 6.2, Linux, simulators, physical Apple devices and stable-release acceptance were not newly qualified; the [acceptance ledger](../../ACCEPTANCE.md) remains authoritative. Further work is required to beat djpeg on the original mixed case, small startup-bound inputs, DCT CLI latency and peak memory. The report deliberately makes no universal performance or product-certification claim.
