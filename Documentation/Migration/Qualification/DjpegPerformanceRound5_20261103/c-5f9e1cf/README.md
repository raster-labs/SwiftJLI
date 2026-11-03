# Qualified C entropy checkpoint — 3 November 2026

**The competitive goal remains open.** Source `5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd` is locally qualified on macOS ARM64. The bounded C entropy kernels improve dense DCT and large ramp/noise lossless decoding while preserving the existing samples, ownership rules and resource ceilings. Small CLI latency, noisy/single-worker DCT API latency and process memory remain gaps. All timings below are owner-authorised provisional measurements under unrelated host activity; local builds, tests and benchmarks were serial.

## Source, behaviour and ownership

- Contract: suite policy **0.10.0**, Apple deployment minima **26.0**, Swift manifest minimum **6.2**. Qualification used Swift **6.4.2**, Xcode **27.2**, macOS **27.0.1** on M4 Max. This is not OS 26 or other-platform qualification.
- Baseline object: `704ddae1bafea95d8a48c01ce35887c5b6413c0d`, production-equivalent to `14f35018d241666358480da2a8527d29ab047627`. The row comparison baseline is `281f3635e003dde60819be21254e982a22b30f3d`, production-equivalent to `e0cfea0fa2f702cb558f6896db03501efcd0b463`. Pinned predecessor remains `b6df774a3c3ecdf4b98971f31543fdd18074ace2`.
- New internal target `SwiftJLIEntropyC` contains original Apache-2.0 code, permitted by PLAT-05. It has no external codec runtime, heap allocation, threads or I/O. Public products and API remain unchanged.
- Eligible accelerated greyscale pipelines call a combined DC/AC C leaf; explicit scalar and the serial batch path retain Swift entropy. Automatic large UInt16, point-transform-zero, left-predictor lossless rows use portable C with a code-zero specialisation and generic fallback. Explicit scalar remains Swift; portable C still reports `scalarCPU`.
- C metadata and compressed input pointers remain inside synchronous borrows. Workers receive internal coefficient storage only. Existing two-slot joining, caller-thread output, cancellation points, exact error sequencing and aborted destination publication remain intact. No full decoded-image handoff copy was added.
- Payload reservations remain **768 KiB** for the DCT pipeline and **8 KiB** for compact DC. Parser and total-memory ceilings are unchanged. The smaller SIMD workspace and serial-C experiments are separate and unaccepted.

## Qualification

| Gate | Result | Evidence |
| --- | --- | --- |
| Full Release | 458 tests / 78 suites; exit 0 | [Receipt](qualification/qualification.json) |
| Focused ASan and TSan | 80 tests / 15 suites each; exit 0; all three C units instrumented | [Instrumentation](qualification/c-instrumentation.json) |
| Standalone combined DC/AC ASan/UBSan | 1,393,276 cases; exit 0 | [Receipt](c-safety/qualification.json) |
| Standalone C row ASan/UBSan | 1,536,287 cases; compile/run exit 0 | [Receipt](c-safety/composed-row-qualification.json) |
| CLI Release | 252 process checks; exit 0 | [Receipt](final/cli-release/report.json) |
| Large lossless independent oracle | Six synthetic profiles, twelve streams, 24 exact output comparisons; 36 commands exit 0 | [Receipt](final/large-lossless-oracle/receipt.json) |
| Large DCT independent oracle | Eight 513 × 257 profiles, 16 direction comparisons, maximum difference 1 within fixed 2/4 limits; 30 commands exit 0 | [Receipt](final/large-dct-oracle/run1/receipt.json) |
| Owned-output API diagnostic | 105 commands exit 0; 24 timing records, eight fixed-quality exclusions, 72 fresh RSS records | [Build](final/owned-output/build.json), [raw results](final/owned-output/results.json) |
| Whole-process CLI | Four version/matrix batches exit 0; exact baseline/candidate output required before timing | [Commands](final/cli-benchmark/cli-benchmark-commands.json) |

The composed row gate also passed 53 focused tests and exact paired DCT/lossless controls. Four immediately paired targeted rounds reduced large ramp latency by 37–50% and noise by 50–53% versus the C-DCT baseline. The full lossless matrix used the same binaries and had no slowdown over 5% in either round; the DCT controls likewise had none. These are native-harness results, distinct from the CLI numbers below. [All raw comparisons](row-performance/decision.json) retain both targeted and full-matrix methods.

The earlier composed-row receipt said safety qualification was pending; the later qualification above closes that local gate. The retained v3 standalone harness failed compilation before execution because of a harness substitution typo; v4 corrected that token without changing production source. Earlier experimental receipts and failures remain historical and are not overwritten.

## Equivalent owned-output API comparison

Both decoder paths run inside the same Swift executable, with static libjpeg-turbo 3.2.1. Timings include allocation and decoding through a retained complete output; destruction is outside timing. Five warmups, 20 samples per engine and two balanced rounds. RSS is the median of three paired fresh processes retaining compressed input and one complete output. Fixed maximum sample differences are 0 for lossless, 2 for 8-bit DCT and 4 for 12-bit DCT. This comparison does not replace CLI timing or memory.

| Fixture / workers | Swift ms, rounds 1 / 2 | libjpeg ms, rounds 1 / 2 | Swift RSS MiB | libjpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| flat-19.jpg / 8 | 0.0081 / 0.0077 | 0.0103 / 0.0108 | 8.766 | 9.328 |
| ramp-19.jpg / 8 | 0.0084 / 0.0078 | 0.0116 / 0.0114 | 8.797 | 9.312 |
| noise-19.jpg / 8 | 0.0086 / 0.0087 | 0.0117 / 0.0117 | 8.766 | 9.312 |
| mixed-19.jpg / 8 | 0.0100 / 0.0081 | 0.0113 / 0.0114 | 8.781 | 9.312 |
| mixed-2048.jpg / 8 | 13.0265 / 12.9941 | 19.0924 / 19.3483 | 21.328 | 21.797 |
| dct12-512.jpg / 8 | 1.2477 / 1.2062 | 1.3118 / 1.2484 | 10.672 | 9.406 |
| dct12-2048.jpg / 8 | 16.5989 / 16.5049 | 19.9563 / 19.8200 | 21.078 | 19.828 |
| dct12-2048.jpg / 1 | 24.7031 / 25.0078 | 19.7706 / 20.0037 | 20.672 | 19.859 |
| flat-8-512.jpg / 8 | 0.0674 / 0.0644 | 0.0816 / 0.0804 | 9.188 | 8.891 |
| flat-12-512.jpg / 8 | 0.0731 / 0.0719 | 0.1641 / 0.1620 | 9.375 | 9.234 |
| noise-8-512.jpg / 8 | 1.1651 / 1.7964 | 1.0855 / 1.0283 | 10.391 | 9.062 |
| noise-12-512.jpg / 8 | 1.4138 / 2.1647 | 1.3485 / 1.6835 | 10.766 | 9.516 |

RGB/progressive 512 and 2048 API cases are excluded because their maximum difference is 3, above the unchanged 8-bit tolerance of 2. No excluded case is counted as a win. Noisy DCT timings varied substantially under shared-host activity; the unfavourable second rounds are retained.

## Whole-process CLI comparison

PNM output goes to `/dev/null`; measurements include process launch, input reads, decode and output. The unchanged harness uses five warmups, 20 samples and two balanced rounds, rotating engine order per sample. Swift still owns a full decoded image; djpeg emits scanlines. This difference is part of the actual CLI memory result.

### djpeg 3.2.1

| Case | Prior Swift ms, rounds 1 / 2 | Updated Swift ms, rounds 1 / 2 | djpeg ms, rounds 1 / 2 | Updated RSS MiB | djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| lossless16-512 | 8.559 / 9.280 | 8.909 / 9.435 | 7.257 / 7.708 | 7.344 / 7.344 | 2.812 / 2.812 |
| lossless16-2048 | 23.203 / 23.198 | 23.191 / 23.319 | 27.682 / 28.120 | 19.078 / 19.078 | 2.844 / 2.844 |
| dct12-512 | 9.747 / 9.819 | 9.693 / 9.827 | 7.598 / 7.568 | 8.453 / 8.391 | 2.203 / 2.203 |
| flat-19 | 7.433 / 9.109 | 7.363 / 9.248 | 5.641 / 7.185 | 6.438 / 6.438 | 2.750 / 2.750 |
| flat-512 | 7.797 / 9.347 | 7.916 / 9.284 | 6.662 / 8.026 | 7.047 / 7.047 | 2.812 / 2.812 |
| flat-2048 | 10.650 / 11.423 | 10.520 / 11.501 | 20.607 / 21.037 | 15.000 / 15.000 | 2.844 / 2.844 |
| flat-3072 | 13.984 / 14.436 | 14.015 / 14.540 | 37.863 / 39.586 | 25.641 / 25.633 | 2.844 / 2.844 |
| ramp-19 | 8.742 / 9.265 | 8.659 / 9.097 | 6.685 / 7.154 | 6.438 / 6.438 | 2.750 / 2.750 |
| ramp-512 | 9.657 / 10.123 | 9.483 / 9.865 | 8.027 / 8.445 | 7.281 / 7.281 | 2.812 / 2.812 |
| ramp-2048 | 21.970 / 22.412 | 18.246 / 18.305 | 27.268 / 27.879 | 17.594 / 17.594 | 2.844 / 2.844 |
| ramp-3072 | 36.667 / 36.345 | 29.471 / 28.901 | 49.530 / 52.096 | 30.219 / 30.219 | 2.844 / 2.844 |
| noise-19 | 8.897 / 9.276 | 9.134 / 9.028 | 7.128 / 7.088 | 6.438 / 6.438 | 2.750 / 2.750 |
| noise-512 | 11.834 / 12.012 | 10.632 / 10.507 | 8.896 / 8.872 | 7.531 / 7.539 | 2.812 / 2.812 |
| mixed-19 | 9.088 / 8.962 | 9.124 / 9.142 | 7.161 / 7.159 | 6.422 / 6.422 | 2.750 / 2.750 |
| mixed-512 | 9.837 / 10.260 | 10.245 / 10.218 | 8.409 / 8.486 | 7.344 / 7.344 | 2.812 / 2.812 |
| mixed-2048 | 23.943 / 23.967 | 23.935 / 24.344 | 28.895 / 29.237 | 19.078 / 19.078 | 2.844 / 2.844 |

### djpeg 3.2.0

| Case | Prior Swift ms, rounds 1 / 2 | Updated Swift ms, rounds 1 / 2 | djpeg ms, rounds 1 / 2 | Updated RSS MiB | djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| lossless16-512 | 8.904 / 8.878 | 8.774 / 8.838 | 7.226 / 7.436 | 7.344 / 7.344 | 2.812 / 2.812 |
| lossless16-2048 | 23.383 / 23.441 | 22.836 / 23.110 | 27.478 / 27.579 | 19.078 / 19.078 | 2.844 / 2.844 |
| dct12-512 | 9.950 / 9.868 | 9.668 / 9.716 | 7.396 / 7.341 | 8.414 / 8.383 | 2.203 / 2.203 |
| flat-19 | 7.634 / 8.642 | 7.648 / 8.693 | 5.388 / 6.878 | 6.438 / 6.438 | 2.734 / 2.734 |
| flat-512 | 7.870 / 9.216 | 7.602 / 9.380 | 6.313 / 7.652 | 7.047 / 7.047 | 2.812 / 2.812 |
| flat-2048 | 10.336 / 11.637 | 10.317 / 11.524 | 17.293 / 19.310 | 15.000 / 15.000 | 2.844 / 2.844 |
| flat-3072 | 14.283 / 14.647 | 14.276 / 14.415 | 33.645 / 33.234 | 25.625 / 25.625 | 2.844 / 2.844 |
| ramp-19 | 8.551 / 9.187 | 8.437 / 9.057 | 6.543 / 7.010 | 6.438 / 6.438 | 2.734 / 2.734 |
| ramp-512 | 9.687 / 10.379 | 9.466 / 9.925 | 8.025 / 8.375 | 7.281 / 7.281 | 2.812 / 2.812 |
| ramp-2048 | 21.541 / 22.564 | 17.570 / 18.693 | 27.240 / 28.231 | 17.594 / 17.594 | 2.844 / 2.844 |
| ramp-3072 | 35.820 / 36.243 | 28.164 / 28.804 | 50.632 / 51.652 | 30.219 / 30.219 | 2.844 / 2.844 |
| noise-19 | 9.005 / 8.774 | 8.963 / 9.001 | 6.900 / 7.078 | 6.438 / 6.438 | 2.734 / 2.734 |
| noise-512 | 11.269 / 11.949 | 10.336 / 10.802 | 8.403 / 8.559 | 7.531 / 7.531 | 2.812 / 2.812 |
| mixed-19 | 9.106 / 9.072 | 9.204 / 8.985 | 7.134 / 6.906 | 6.422 / 6.422 | 2.734 / 2.734 |
| mixed-512 | 10.385 / 9.752 | 10.261 / 10.288 | 8.291 / 8.357 | 7.344 / 7.344 | 2.812 / 2.812 |
| mixed-2048 | 23.279 / 24.398 | 23.813 / 24.519 | 28.151 / 28.812 | 19.078 / 19.078 | 2.844 / 2.844 |

Five unique large-lossless inputs beat both djpeg versions in both rounds: flat 2048/3072, ramp 2048/3072 and mixed 2048. `lossless16-2048` is a byte-identical alias of `mixed-2048`, not an additional win. The row optimisation reduces large-ramp CLI latency by about 17–21% versus the preceding Swift build. All measured whole-process memory results and small CLI cases still favour djpeg.

Noise 2048/3072 and mixed 3072 remain rejected by both Swift builds under unchanged default workspace admission, so they have no accepted CLI timing. RGB/progressive 512 remain outside the fixed quality gate. No limit, tolerance or benchmark eligibility was relaxed.

Production regressions are covered by [DC/AC differential tests](../../../../../Tests/SwiftJLITests/Native/CDCTDecoderTests.swift), [lossless row tests](../../../../../Tests/SwiftJLITests/Native/CLosslessRowTests.swift), [public pipeline tests](../../../../../Tests/SwiftJLITests/Native/CACPublicPipelineTests.swift) and [joined-worker tests](../../../../../Tests/SwiftJLITests/Native/PipelinedGreyscaleTests.swift). New large synthetic oracle provenance is in the [DCT generator and input manifest](final/large-dct-oracle/source-manifest.json) and [lossless generator audit](final/large-lossless-oracle/source-audit-sidecar.json); no patient images or re-licensed fixtures were added.

## Remaining gates and limitations

Current-source remote CI, full-suite ASan/TSan, ASan CLI, Linux/Intel/Apple simulator and physical-device checks were not rerun in this checkpoint. Earlier platform passes refer to their own pins. The public API, sample/copy/lifetime contract and licensed fixtures are unchanged; synthetic fixture generators, source hashes, exact commands and errors are retained here. `peakWorkspaceBytes` remains unknown and is not inferred from RSS. This checkpoint establishes local correctness and measured improvements, not universal superiority, stable-release acceptance or completion of the competitive goal.

[Archive manifest](manifest.json) records original paths and byte hashes; generated executables, objects and image payloads are omitted. Retained fixture/output hashes identify those artefacts.
