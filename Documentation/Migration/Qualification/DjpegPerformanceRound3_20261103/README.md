# JPEG optimisation checkpoint — 3 November 2026

**SwiftJLI now beats both pinned djpeg versions on all five eligible large lossless cases. The goal of winning every benchmark remains open.** Small CLI inputs and DCT12 CLI latency still favour djpeg. All successful baseline/candidate outputs in the measured corpus remain identical.

Production and test source: `5351088d3bb4630a32de6509e4d62210ad14aaa0` (including `714e287b0548b26f6189a07d97ff19d44548fba6`). Baseline: `c7791d5635e46f3ef30f1dd1f14d7189e228a5c0`. Suite policy **0.10.0**, Swift 6.2 manifest minimum and Apple OS 26.0 floor are unchanged. [Source hashes](source-manifest.json) and [binary/compiler pins and exact benchmark commands](benchmark-commands.json) identify the executed artefacts.

## Implementation and fidelity

- Lossless lookup dispatch now places the fast path directly in the row loop, avoiding an out-of-line helper for every sample. Bulk refill handles an empty 64-bit accumulator explicitly and uses masked shifts only within proven private bounds.
- Predictor-1 scans whose canonical one-bit zero code means a zero difference can consume consecutive zero differences together. Output uses the same modulo prediction, point transform and clamping, with no history/image-sized scratch for this path. Other symbols use the existing decoder; restarts and row cancellation remain bounded.
- Single-component sequential DCT scans borrow the coefficient plane once for the synchronous scan. Quantisation, IDCT, colour and rounding arithmetic remain unchanged.
- Structural admission retains the exact immutable input and validated entropy ranges; marker parsing reuses those ranges instead of scanning entropy a second time. No structural check is removed.
- The CLI reads regular files directly into a size-admitted owning buffer, retaining chunked cancellation, shrink/growth handling, EOF checking and the existing pipe path.

No public API, precision, fidelity tolerance, resource limit, backend policy or external-codec dependency changes. No raw pointer outlives its owner or synchronous borrow. Existing joined-worker lifetime and copy reporting remain in place. Resource admission remains conservative; `peakWorkspaceBytes` remains unknown.

## Controlled CLI comparisons

Apple Swift **6.4.2**, Xcode **27.2**, M4 Max (16 cores, 64 GiB), macOS **27.0.1**, AC power. Same baseline executable/library object as the preceding qualified checkpoint, with hashes verified; candidate rebuilt in release mode with four jobs. **5 warmups, 20 samples, 2 rounds**, balanced rotating/reversed tool order, no concurrent builds/tests/profilers. Wall time includes process launch, read, decode and PNM output to `/dev/null`, measured through Darwin `/usr/bin/time -l`. RSS is whole-process peak resident memory, not codec workspace.

Tables show the mean of two round medians. A win requires **more than 5% lower latency in each round**. The 3.2.0 and 3.2.1 comparisons are separate balanced batches; absolute times between batches do not isolate version changes. `lossless16` and corresponding `mixed` fixtures are byte-identical aliases, not independent wins.

### djpeg 3.2.1

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift latency reduction vs djpeg | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 9.510 | 9.173 | 7.494 | -22.4% | 7.81 | 2.81 |
| lossless16 2048² | 28.250 | 23.862 | 27.271 | +12.5% **win** | 27.98 | 2.84 |
| dct12 512² | 11.274 | 10.902 | 7.682 | -41.9% | 12.02 | 2.20 |
| flat 19² | 8.142 | 8.143 | 6.157 | -32.2% | 6.50 | 2.75 |
| flat 512² | 9.007 | 8.572 | 7.226 | -18.6% | 7.11 | 2.81 |
| flat 2048² | 18.589 | 11.065 | 20.314 | +45.5% **win** | 16.02 | 2.84 |
| flat 3072² | 30.840 | 14.773 | 37.907 | +61.0% **win** | 27.89 | 2.84 |
| ramp 19² | 8.473 | 8.359 | 6.562 | -27.4% | 6.50 | 2.75 |
| ramp 512² | 9.578 | 9.529 | 7.979 | -19.4% | 7.75 | 2.81 |
| ramp 2048² | 22.312 | 22.011 | 26.665 | +17.5% **win** | 23.69 | 2.84 |
| ramp 3072² | 37.688 | 37.604 | 49.063 | +23.4% **win** | 41.56 | 2.84 |
| noise 19² | 8.878 | 8.875 | 7.002 | -26.8% | 6.50 | 2.75 |
| noise 512² | 11.630 | 11.570 | 8.776 | -31.8% | 8.00 | 2.81 |
| mixed 19² | 8.843 | 8.694 | 6.963 | -24.9% | 6.48 | 2.75 |
| mixed 512² | 10.206 | 10.230 | 8.552 | -19.6% | 7.81 | 2.81 |
| mixed 2048² | 29.427 | 24.843 | 28.379 | +12.5% **win** | 27.98 | 2.84 |

[Original raw results](cli-original-3.2.1.json) · [Pattern raw results](cli-lossless-patterns-3.2.1.json)

### djpeg 3.2.0

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift latency reduction vs djpeg | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 9.280 | 8.957 | 7.196 | -24.5% | 7.81 | 2.81 |
| lossless16 2048² | 27.741 | 23.517 | 26.775 | +12.2% **win** | 27.98 | 2.84 |
| dct12 512² | 10.602 | 10.129 | 7.180 | -41.1% | 12.02 | 2.20 |
| flat 19² | 7.797 | 7.676 | 5.720 | -34.2% | 6.50 | 2.73 |
| flat 512² | 8.383 | 7.845 | 6.440 | -21.8% | 7.11 | 2.81 |
| flat 2048² | 17.893 | 10.606 | 16.857 | +37.1% **win** | 16.02 | 2.84 |
| flat 3072² | 29.788 | 14.017 | 30.367 | +53.8% **win** | 27.89 | 2.84 |
| ramp 19² | 8.275 | 8.265 | 6.270 | -31.8% | 6.50 | 2.73 |
| ramp 512² | 9.604 | 9.418 | 7.657 | -23.0% | 7.75 | 2.81 |
| ramp 2048² | 21.936 | 21.758 | 26.092 | +16.6% **win** | 23.69 | 2.84 |
| ramp 3072² | 36.463 | 36.447 | 48.847 | +25.4% **win** | 41.56 | 2.84 |
| noise 19² | 8.366 | 8.561 | 6.453 | -32.7% | 6.50 | 2.73 |
| noise 512² | 11.169 | 10.987 | 7.931 | -38.5% | 8.00 | 2.81 |
| mixed 19² | 8.163 | 8.331 | 6.333 | -31.5% | 6.48 | 2.73 |
| mixed 512² | 9.869 | 9.611 | 7.958 | -20.8% | 7.81 | 2.81 |
| mixed 2048² | 28.303 | 23.789 | 27.269 | +12.8% **win** | 27.98 | 2.84 |

[Original raw results](cli-original-3.2.0.json) · [Pattern raw results](cli-lossless-patterns-3.2.0.json)

The five independent large-image wins are **flat2048, flat3072, ramp2048, ramp3072 and mixed2048**, against both versions. The original mixed2048 case is approximately **12.5% faster than 3.2.1 and 12.2% faster than 3.2.0**. It previously trailed both. These are finite single-host results, not a universal speed claim.

## Quality and exclusions

Every accepted CLI baseline/candidate comparison has identical complete PNM bytes and samples. Lossless djpeg comparisons require zero difference. DCT12 retains tolerance 4 and observed difference 1. The existing RGB8/progressiveRGB8 cases differ from djpeg by 3, above their fixed tolerance 2, and remain excluded from timing acceptance. Noise2048/noise3072/mixed3072 remain resource-limit exit 5 under the unchanged CLI 512 MiB workspace ceiling. No tolerance or admission ceiling was relaxed to obtain wins.

## Public-library latency

These allocated-output `Decoder.decode` measurements exclude process launch, file reads, verification and PNM output. They compare SwiftJLI revisions, not an in-process libjpeg API. Same 5/20/two-round method; sixteen lossless outputs match source bytes and twelve DCT outputs match prior output hashes. Both lossless revisions use the same explicit 8/10 GiB workspace/total admission for the expanded native matrix.

| Lossless case | Prior ms | Updated ms | Latency reduction |
|---|---:|---:|---:|
| flat-19 | 0.0091 | 0.0082 | +10.2% |
| flat-512 | 0.5342 | 0.0977 | +81.7% |
| flat-2048 | 7.9361 | 0.8209 | +89.7% |
| flat-3072 | 17.6140 | 1.8984 | +89.2% |
| ramp-19 | 0.0081 | 0.0080 | +1.7% |
| ramp-512 | 0.7395 | 0.6871 | +7.1% |
| ramp-2048 | 10.9087 | 10.5606 | +3.2% |
| ramp-3072 | 23.1216 | 22.4609 | +2.9% |
| noise-19 | 0.0085 | 0.0084 | +2.2% |
| noise-512 | 2.4269 | 2.2645 | +6.7% |
| noise-2048 | 37.4917 | 35.0359 | +6.6% |
| noise-3072 | 83.8185 | 78.5747 | +6.3% |
| mixed-19 | 0.0084 | 0.0083 | +1.7% |
| mixed-512 | 1.0939 | 0.8180 | +25.2% |
| mixed-2048 | 16.5404 | 12.3835 | +25.1% |
| mixed-3072 | 37.1504 | 27.7641 | +25.3% |

| DCT case | Prior ms | Updated ms | Latency reduction |
|---|---:|---:|---:|
| dct12-512.jpg | 2.1498 | 1.7618 | +18.0% |
| dct12-2048.jpg | 31.2927 | 24.7851 | +20.8% |
| rgb8-512.jpg | 3.2893 | 3.2281 | +1.9% |
| rgb8-2048.jpg | 43.8696 | 42.0892 | +4.1% |
| progressiveRGB8-512.jpg | 4.4841 | 4.4180 | +1.5% |
| progressiveRGB8-2048.jpg | 59.9946 | 59.1398 | +1.4% |
| xyb8-512.jpg | 9.8938 | 9.7302 | +1.7% |
| xyb8-2048.jpg | 148.9322 | 145.1990 | +2.5% |
| flat-8-512.jpg | 0.8494 | 1.1230 | -32.2% |
| flat-12-512.jpg | 0.8619 | 0.5154 | +40.2% |
| noise-8-512.jpg | 2.0847 | 1.6518 | +20.8% |
| noise-12-512.jpg | 2.5087 | 2.0295 | +19.1% |

[Native lossless samples](native-lossless.json) · [Native DCT samples](native-dct.json). Large flat lossless improves about **89%**, mixed lossless about **25%** versus the preceding checkpoint. The raw rounds and p95 retain small-case variability; averaged figures are not proof of zero regressions.

One flat8 DCT512 candidate round varied from 0.684 to 3.785 ms and produced the negative average shown above. Its cause was not established. A targeted four-round follow-up with the exact same binaries and reversed order measured **33.0–36.9% lower latency** with identical output hashes. [Original samples](native-dct.json) remain unchanged; [follow-up samples](flat-dct-follow-up.json) are separate. No repeatable regression was established, and the unstable original average is not hidden.

## Qualification and provenance

Final release suite: **388 tests / 60 suites, exit 0** ([log](final-release-tests.log)). Full ASan: **388 tests / 60 suites**, no finding. Release and ASan CLI: **250 process checks each**. Focused TSan: **45 tests / 10 suites**, no finding. Lossless interoperability: **210 cases in each direction**. DCT interoperability: **48 profiles in both directions**, maximum sample difference 2 within unchanged tolerances. All exited 0; all seven contract hashes remain unchanged. [Exact commands and outcomes](validation.json).

[36 independent large zero-category cases](zero-oracle.json) pass exact comparisons with both SwiftJLI and djpeg. The retained generator uses cjpeg 3.2.1 with explicit precision, point transform, restart and optimisation flags, and verifies that every fixture actually selects the one-bit-zero path. All inputs are synthetic. Original benchmark fixture provenance remains pinned to JLISwift `b6df774a3c3ecdf4b98971f31543fdd18074ace2` in [the first report](../DjpegPerformance20261102/README.md); expanded lossless and DCT generators are retained in [round two](../DjpegPerformanceRound2_20261102/README.md).

[Zero-run tests](../../../../Tests/SwiftJLITests/Native/ZeroRunLosslessTests.swift) cover four precisions, point transforms, restarts, changing plateaus, offset/padded rows, truncated entropy, invalid extents and deadlines. [Greyscale scan tests](../../../../Tests/SwiftJLITests/Native/SequentialGreyscaleDecoderTests.swift) cover coefficient values, scan extents, lookup/scalar paths, restarts, sentinels and failures. [Envelope tests](../../../../Tests/SwiftJLITests/ValidatedEnvelopeTests.swift) compare independent traversal, progressive table snapshots, immutable ownership, malformed streams and cancellation. Eight added CLI checks compare regular files with pipes across 64 KiB read boundaries.

Experiment receipts and the initial oversized test-fixture rejection are retained under [Experiments](Experiments/notes.json). One diagnostic zero-run experiment inherited a stale baseline revision label; its correction and actual object identity are explicitly recorded there. Final benchmark source/binary pins are separate and correct. No third-party code or fixture licence was changed.

## Remaining work

The goal remains active: small CLI decodes and DCT12 CLI latency still trail djpeg, and process RSS remains substantially higher. Swift/Foundation process startup remains a measured source of overhead from the preceding investigation; native library improvements do not remove it. Further work must preserve the same fidelity, resource and failure behaviour. This round qualifies local macOS only; Swift 6.2, Linux, simulators, physical devices and stable-release acceptance were not newly qualified.
