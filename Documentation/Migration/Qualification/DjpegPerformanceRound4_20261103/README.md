# JPEG decoding and memory optimisation — 3 November 2026

**Memory use is substantially lower without changing decoded samples. The goal of beating djpeg on every benchmark remains open. All timings in this report are provisional.**

The owner authorised provisional timings because a background virtual machine was continuously using approximately four CPU cores. Recorded snapshots also show an independent SwiftJLS benchmark using approximately one core. No SwiftJLI build, correctness test or profiler overlapped these final timing batches. This is not a controlled speed qualification and does not establish new accepted wins. Raw rounds, p95, outliers, exclusions and host activity are retained.

Baseline: `8ae2762710d6279cd92222f5bb5ca95f042f694e` (production sources identical to the preceding `5351088d3bb4630a32de6509e4d62210ad14aaa0` checkpoint). Final production and test source: `0a8acd72ddeac6fb1911457ae28b689eef0e9db1`. Suite policy **0.10.0**, Swift 6.2 manifest minimum, Swift 6.4 qualified primary toolchain and Apple OS 26.0 deployment floor remain unchanged. [Source hashes](source-manifest.json), [benchmark commands and binary/compiler pins](benchmarks/benchmark-commands.json), and [validation evidence](validation/README.md) identify the executed artefacts. This report and evidence are subsequent documentation-only changes.

## Implemented changes

- DCT reconstruction uses at most 1,024 blocks of scratch per worker instead of full-frame scratch; preview paths omit an unused full-frame allocation.
- Eligible full-resolution sequential greyscale DCT decodes stream coefficients through 1,024-block batches directly into the destination. Explicit one-worker decoding uses this path at all supported sizes. Automatic accelerated decoding uses it up to 4,096 blocks; scalar decoding up to 2,048 blocks. Larger default decodes retain the existing parallel coefficient/plane path. Restart/DC state, cancellation, sample rounding and Float output bits are preserved.
- Resource admission uses the same immutable backend/worker plan as dispatch. For streaming, the old `sampleCount * 128` reservation becomes `min(1024, ceil(width/8) * ceil(height/8)) * 64 * (sizeof(Int32) + 2 * sizeof(Float))`, at most 786,432 bytes. The compressed-input reservation (`compressedBytes * 64 + 1 MiB`) and all resource ceilings remain unchanged. Consequently, a qualifying streaming operation can now fit a budget that previously rejected it; this is an intentional admission change, not a higher limit. Default 2048² DCT still uses the conservative parallel reservation.
- Parsing and entropy scans retain one immutable compressed-input owner with validated ranges. The public Data-to-array and per-scan entropy copies are removed. On Apple platforms, a checked NSData-to-CFData bridge and scoped CF byte access avoid deferred autorelease retention. Pointer identity, copy-on-write independence and prompt final release are tested. Foundation representation may still require a copy on other platforms; universal zero-copy input is not claimed.
- The CLI uses a one-byte EOF probe after exact regular-file reads and one nonblocking stdout scope per output, preserving input-growth limits, cancellation, deadlines and inherited descriptor flags.

No public API, sample precision, signedness, colour transform, fidelity tolerance or external-codec dependency changes. `OwnedImageStorage` still zero-fills. Workers retain input owners and join before release; the caller's output pointer is used serially and does not cross a concurrent worker scope. `peakWorkspaceBytes` remains unknown: the process RSS figures below are not that metric.

## Single-decode process memory

A fresh native process performs one public allocated-output decode, retaining the compressed input and one final output. There is no verification output copy or CryptoKit import in this probe. Three balanced paired trials per case; table values are median peak RSS from Darwin `/usr/bin/time -l`. Both revisions use explicit 8 GiB workspace / 10 GiB total admission for this expanded native probe. These limits are test configuration, not changed product defaults. Output length and an edge-byte summary match here; full-output equality is checked separately by the native matrix and regression tests. This probe compares SwiftJLI revisions, not an in-process libjpeg API.

| Case | Worker ceiling | Prior RSS MiB | Updated RSS MiB | Reduction |
|---|---:|---:|---:|---:|
| dct12-512.jpg | 8 | 12.11 | 8.33 | 31.2% |
| dct12-2048.jpg | 8 | 88.41 | 54.28 | 38.6% |
| rgb8-512.jpg | 8 | 16.33 | 14.12 | 13.5% |
| rgb8-2048.jpg | 8 | 148.72 | 114.06 | 23.3% |
| progressiveRGB8-512.jpg | 8 | 17.16 | 16.03 | 6.6% |
| progressiveRGB8-2048.jpg | 8 | 148.80 | 114.08 | 23.3% |
| dct12-512.jpg | 1 | 12.05 | 8.36 | 30.6% |
| dct12-2048.jpg | 1 | 88.22 | 18.75 | 78.7% |
| mixed-2048.jpg | 8 | 28.00 | 19.19 | 31.5% |
| noise-2048.jpg | 8 | 30.78 | 22.73 | 26.1% |

The **78.7%** reduction for 2048² greyscale DCT compares one worker against one worker. The default worker ceiling of eight reduces the same case by **38.6%**. These must not be conflated. RSS varies with allocator/runtime/host conditions; the bounded allocation change is structural, while these percentages describe the recorded host trials. [All 60 process measurements and commands](benchmarks/one-shot-memory.json) · [probe source](benchmarks/one-shot-memory.swift).

## Provisional whole-process comparisons with djpeg

Apple Swift **6.4.2**, Xcode **27.2**, M4 Max (16 cores, 64 GiB), macOS **27.0.1**, AC power. Same compiler and matched release builds; no code-generation optimisation flag changes. Five warmups, 20 measured samples, two balanced rounds. Wall time includes process launch, file read, decode and PNM output to `/dev/null`. RSS is whole-process peak resident memory. The two djpeg versions run in separate batches, so absolute times between batches do not isolate version differences.

Values below are means of round medians. Positive percentages mean SwiftJLI has lower latency than djpeg. “Both rounds >5%” describes the numerical observation only, not an accepted speed win under this contention. `lossless16` and corresponding `mixed` images are byte-identical aliases; do not count both as independent successes.

### djpeg 3.2.1 — provisional

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift reduction vs djpeg | Both rounds >5% | Prior RSS MiB | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| lossless16 512² | 8.810 | 8.739 | 7.332 | -19.2% | no | 7.81 | 7.33 | 2.81 |
| lossless16 2048² | 24.130 | 23.111 | 27.574 | +16.2% | yes | 27.98 | 19.06 | 2.84 |
| dct12 512² | 10.506 | 10.263 | 7.642 | -34.3% | no | 12.00 | 8.19 | 2.20 |
| flat 19² | 8.166 | 8.250 | 6.484 | -27.2% | no | 6.50 | 6.44 | 2.75 |
| flat 512² | 8.539 | 8.534 | 7.293 | -17.0% | no | 7.11 | 7.06 | 2.81 |
| flat 2048² | 11.452 | 11.175 | 20.720 | +46.1% | yes | 16.02 | 15.02 | 2.84 |
| flat 3072² | 14.895 | 14.345 | 38.255 | +62.5% | yes | 27.89 | 25.66 | 2.84 |
| ramp 19² | 8.853 | 8.785 | 6.792 | -29.3% | no | 6.50 | 6.44 | 2.75 |
| ramp 512² | 9.871 | 9.867 | 8.280 | -19.2% | no | 7.75 | 7.27 | 2.81 |
| ramp 2048² | 22.767 | 22.358 | 26.941 | +17.0% | yes | 23.69 | 17.58 | 2.84 |
| ramp 3072² | 38.984 | 37.362 | 51.127 | +26.9% | yes | 41.56 | 30.21 | 2.84 |
| noise 19² | 9.120 | 9.336 | 7.381 | -26.5% | no | 6.50 | 6.44 | 2.75 |
| noise 512² | 11.972 | 11.962 | 8.969 | -33.4% | no | 8.00 | 7.52 | 2.81 |
| mixed 19² | 9.306 | 9.309 | 7.479 | -24.5% | no | 6.48 | 6.45 | 2.75 |
| mixed 512² | 10.570 | 10.374 | 8.753 | -18.5% | no | 7.81 | 7.33 | 2.81 |
| mixed 2048² | 25.412 | 24.770 | 28.986 | +14.5% | yes | 27.98 | 19.06 | 2.84 |

[Original raw results](benchmarks/cli-original-3.2.1.json) · [Pattern raw results](benchmarks/cli-lossless-patterns-3.2.1.json)

### djpeg 3.2.0 — provisional

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift reduction vs djpeg | Both rounds >5% | Prior RSS MiB | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| lossless16 512² | 8.941 | 8.876 | 7.284 | -21.9% | no | 7.81 | 7.33 | 2.81 |
| lossless16 2048² | 24.412 | 23.484 | 27.819 | +15.6% | yes | 27.98 | 19.07 | 2.84 |
| dct12 512² | 10.596 | 10.210 | 7.514 | -35.9% | no | 12.02 | 8.20 | 2.20 |
| flat 19² | 8.140 | 8.201 | 6.116 | -34.1% | no | 6.50 | 6.45 | 2.73 |
| flat 512² | 8.486 | 8.457 | 6.988 | -21.0% | no | 7.11 | 7.06 | 2.81 |
| flat 2048² | 11.142 | 11.067 | 17.823 | +37.9% | yes | 16.02 | 15.02 | 2.84 |
| flat 3072² | 14.930 | 14.744 | 30.900 | +52.3% | yes | 27.91 | 25.65 | 2.84 |
| ramp 19² | 8.584 | 8.807 | 6.753 | -30.4% | no | 6.50 | 6.44 | 2.73 |
| ramp 512² | 9.977 | 9.925 | 8.126 | -22.1% | no | 7.75 | 7.27 | 2.81 |
| ramp 2048² | 22.804 | 22.052 | 27.724 | +20.5% | yes | 23.69 | 17.59 | 2.84 |
| ramp 3072² | 38.352 | 36.835 | 50.473 | +27.0% | yes | 41.57 | 30.22 | 2.84 |
| noise 19² | 8.802 | 9.091 | 6.988 | -30.1% | no | 6.50 | 6.45 | 2.73 |
| noise 512² | 11.872 | 11.937 | 8.739 | -36.6% | no | 8.00 | 7.53 | 2.81 |
| mixed 19² | 9.004 | 9.054 | 6.941 | -30.5% | no | 6.48 | 6.44 | 2.73 |
| mixed 512² | 10.006 | 9.967 | 8.465 | -17.7% | no | 7.81 | 7.33 | 2.81 |
| mixed 2048² | 25.369 | 24.226 | 28.648 | +15.4% | yes | 27.99 | 19.07 | 2.84 |

[Original raw results](benchmarks/cli-original-3.2.0.json) · [Pattern raw results](benchmarks/cli-lossless-patterns-3.2.0.json)

The same five independent large lossless cases remain numerically more than 5% faster than both djpeg versions in both rounds: flat2048, flat3072, ramp2048, ramp3072 and mixed2048. Earlier controlled evidence is preserved in [round three](../DjpegPerformanceRound3_20261103/README.md). **Small CLI cases and DCT12 CLI latency still favour djpeg, and every accepted CLI case still uses more process RSS than djpeg.** The 512² DCT12 CLI memory falls from about 12.0 to 8.2 MiB, but djpeg uses about 2.2 MiB.

Every successful baseline/candidate CLI comparison has identical complete PNM bytes and samples. Lossless comparisons with djpeg require zero sample difference. DCT12 retains tolerance four and observes difference one. RGB8 and progressiveRGB8 512² still differ from djpeg by three, above their unchanged tolerance two, so neither receives accepted timings. Noise2048/noise3072/mixed3072 still exit five under the unchanged default CLI workspace ceiling in both Swift revisions; they are excluded. No tolerance is relaxed to obtain a performance claim.

## Provisional public-library latency

Public allocated-output `Decoder.decode` timing excludes process launch, file reads, verification and PNM output. These measurements compare SwiftJLI revisions; they are not a libjpeg API benchmark. Five warmups, 20 samples and two rounds per case. Sixteen lossless outputs match the synthetic source bytes, and twelve DCT outputs match the preceding revision's complete output hash. The one-shot memory probe above is separate from these repeated native harnesses, which may retain a checked image and verification copy.

| DCT case | Prior ms | Updated ms | Reduction |
|---|---:|---:|---:|
| dct12-512.jpg | 1.8362 | 1.6977 | +7.5% |
| dct12-2048.jpg | 25.7756 | 25.6694 | +0.4% |
| rgb8-512.jpg | 3.6472 | 3.4991 | +4.1% |
| rgb8-2048.jpg | 44.6671 | 44.4353 | +0.5% |
| progressiveRGB8-512.jpg | 4.7765 | 4.7545 | +0.5% |
| progressiveRGB8-2048.jpg | 62.0797 | 61.9124 | +0.3% |
| xyb8-512.jpg | 9.9515 | 9.9882 | -0.4% |
| xyb8-2048.jpg | 150.7209 | 151.3562 | -0.4% |
| flat-8-512.jpg | 0.5747 | 0.4972 | +13.5% |
| flat-12-512.jpg | 0.5446 | 0.4970 | +8.7% |
| noise-8-512.jpg | 1.7269 | 1.6242 | +5.9% |
| noise-12-512.jpg | 2.1425 | 1.9941 | +6.9% |

| Lossless case | Prior ms | Updated ms | Reduction |
|---|---:|---:|---:|
| flat-19 | 0.0085 | 0.0086 | -2.2% |
| flat-512 | 0.0972 | 0.0941 | +3.2% |
| flat-2048 | 0.8625 | 0.8326 | +3.5% |
| flat-3072 | 2.0134 | 1.8017 | +10.5% |
| ramp-19 | 0.0083 | 0.0081 | +2.5% |
| ramp-512 | 0.7079 | 0.6850 | +3.2% |
| ramp-2048 | 10.8554 | 10.7861 | +0.6% |
| ramp-3072 | 22.8528 | 22.7141 | +0.6% |
| noise-19 | 0.0085 | 0.0091 | -8.0% |
| noise-512 | 2.2639 | 2.2359 | +1.2% |
| noise-2048 | 35.6639 | 35.3540 | +0.9% |
| noise-3072 | 80.2370 | 79.4897 | +0.9% |
| mixed-19 | 0.0081 | 0.0080 | +1.2% |
| mixed-512 | 0.8423 | 0.8232 | +2.3% |
| mixed-2048 | 12.6716 | 12.5919 | +0.6% |
| mixed-3072 | 28.3379 | 27.6648 | +2.4% |

[Native DCT raw samples](benchmarks/native-dct.json) · [Native lossless raw samples](benchmarks/native-lossless.json). The native lossless helper's generic “round4 working experiment” candidate label is superseded by the exact final source pin in the orchestration manifest; its linked object hash matches that manifest. Individual round changes and p95 remain available; these averages are not proof of zero regressions.

Two tiny native lossless cases show regressions worth retaining: flat19 is 5.93% slower in round one (2.21% slower on average), and noise19 is 11.28% slower in round two (8.00% slower on average, from 8.459 to 9.136 microseconds). No native DCT or CLI baseline-to-candidate case regresses by more than 5% in either round. The tiny-case costs need an idle-host follow-up; contention prevents attributing them confidently to code or scheduling. They are not removed from the results.

## Qualification, ownership and failure coverage

At `82d4b25510daceeddb40d1a2395e683203d76526`, full release and full ASan each pass **403 tests / 63 suites**, release and ASan CLI each pass **252 process checks**, and focused TSan passes **67 tests / 14 suites**. Independent lossless interoperability passes **210 cases per direction**; DCT interoperability passes **48 profiles in both directions**, maximum observed difference two within unchanged 8-bit/12-bit tolerances of two/four. All exit zero and all seven common contract hashes remain unchanged.

The final `0a8acd7` refinement preserves scalar parallelism above 2,048 blocks and makes ownership assertions portable. Full release passes **403 / 63** again; affected ASan and TSan each pass **23 / 4**, with no finding. Full ASan, CLI and oracle counts above belong to `82d4b25`; they were not rerun in full at `0a8acd7`. [Exact commands, source pins, outcomes and raw reports](validation/README.md) distinguish those runs.

- [Bounded DCT tests](../../../../Tests/SwiftJLITests/Native/BoundedDCTWorkspaceTests.swift): odd edges, batch boundaries, padded/misaligned integer and Float destinations, parallel output identity and invalidation after later truncation.
- [Sequential greyscale tests](../../../../Tests/SwiftJLITests/Native/SequentialGreyscaleDecoderTests.swift): restarts at 1,023/1,024/1,025-block boundaries, lookup modes/precision and cancellation before reuse.
- [Compressed input ownership tests](../../../../Tests/SwiftJLITests/CompressedInputOwnershipTests.swift): Apple input pointer identity, shared owner/scan storage, copy-on-write/drop, mutable Foundation snapshots, exact final release, 16 repeated unpooled decodes, stuffed/restart/truncated readers and eight joined readers. Platform-dependent input bridging is acknowledged; ownership release assertions remain exact.
- [Workspace admission tests](../../../../Tests/SwiftJLITests/StreamingWorkspaceAdmissionTests.swift): exact and one-below workspace/total/input/output budgets, no destination borrow on rejection, reuse, odd/padded outputs, scalar/accelerated/Float paths, overflow and 2,048/2,049 plus 4,096/4,097-block dispatch boundaries.
- [CLI tests](../../../../Scripts/test-cli.py): descriptor flag restoration, file/pipe output parity, size boundaries and existing failure/deadline checks. Five isolated fstat size-hint experiments additionally preserve exact shrinking/growing outputs and reject growth over the limit with no stdout publication.

All fixtures are synthetic. The original generators remain pinned to JLISwift `b6df774a3c3ecdf4b98971f31543fdd18074ace2` in [the first report](../DjpegPerformance20261102/README.md); expanded lossless/DCT generators and provenance are retained in [round two](../DjpegPerformanceRound2_20261102/README.md). Final fixture hashes are in the raw results. No third-party source, licence or fixture is relicensed.

## Rejected experiments and remaining gates

[Experiment receipts](experiments/README.md) retain failures as well as successes. General lossless magnitude-prefetch refill regressed ramps; a simple Data-backed hot reader regressed native decoding; a Span-storing reader required unavailable experimental lifetime support. None ships. The original NSData byte getter delayed final release until an autorelease drain; the accepted checked CF getter releases promptly without that pool. Grouped parallel streaming windows reduced memory but repeatedly exceeded a 5% latency regression, so they were rejected. A 4,096-block scalar streaming threshold also regressed decoding and was reduced to 2,048. No experimental compiler flags or unsafe cast were introduced.

The existing baseline PR CI run [41586828694](https://github.com/raster-labs/SwiftJLI/actions/runs/41586828694) has unresolved native macOS release signal-11 crashes on both Intel and arm64 using Apple Swift 6.3.3/Xcode 26.6. Debug, Linux Swift 6.2/6.4, consumer, contract, Apple SDK and simulator jobs passed on that older source. Local Swift 6.4.2 release and sanitiser tests do not prove a fix for those failures. Failure-only CI crash-report/test-bundle uploads were added without changing job toolchains or failure status. The new head requires CI; no new Linux, simulator or physical-device qualification is claimed here.

The next performance boundary is small-process startup and the remaining DCT work. Full-output ownership in the public API also has a different memory cost from djpeg's scanline CLI. This batch reduces that cost but does not eliminate the measured gap. Controlled idle-host timing, CI failure diagnosis and the existing platform/stable-release gates remain open. No stable release, universal speed win or completed optimisation goal is claimed.
