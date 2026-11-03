# JPEG optimisation — fifth round, 3 November 2026

**The overall djpeg goal remains open.** The latest completed local evidence is the [joined pipeline checkpoint at `14f3501`](pipeline-14f3501/README.md): 436 Release tests, focused ASan/TSan, CLI checks, DCT oracle and provisional native/API comparisons. Its production-equivalent tested source is `704ddae`. The [latest 14f CI result](pipeline-14f3501/ci-14f-summary.json) has four Linux test failures and six unavailable Apple ARM jobs; the local counts do not imply a remote pass. [Verify the report archives](verify_report.py) without rebuilding.

## Retained f4a05be checkpoint

The following report and tables remain pinned to `f4a05be`. They are historical evidence, including the latest whole-process CLI benchmark matrix; they are not silently relabelled as pipeline measurements. All timings are provisional under unrelated host activity.

Source: `f4a05be9f3003a48adaa840abd48fcf6071f009d`; baseline: `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8` (production equivalent to `0a8acd72ddeac6fb1911457ae28b689eef0e9db1`). Suite policy **0.10.0**, Apple OS **26.0** floor, Swift **6.2** manifest minimum and Swift **6.4** primary toolchain are unchanged. The executed host used Apple Swift **6.4.2**, Xcode **27.2**, macOS **27.0.1**, M4 Max, 16 cores and 64 GiB RAM.

## Changes and safety

- Parsed Huffman tables omit unused encoder maps; small-image validation avoids temporary sets and batches cancellation checks within a bounded sample count. A specialised untransformed UInt16 left-predictor loop recovers the large-ramp regression.
- DCT reconstruction keeps canonical 1,024-block shapes across worker counts, preserving Float bits on Intel as well as ARM. A nominal task-local callback wrapper addresses the reproduced Swift 6.3 Release metadata crash.
- AC entropy decoding prefetches only through the existing FF-free bulk reader. Stuffing, markers, truncation, error handling and quality tolerances are preserved.
- Streaming coefficients reuse consumed storage for reconstructed output. Large greyscale scans use at most eight joined internal tiles with a 4 MiB payload; workers compact samples internally and only the caller writes provider storage.
- A scan-local AC table containing only zero magnitude categories selects compact DC storage: at most 1,024 Int32/Float values, 8 KiB total. It retains full resolution and precision. Constant blocks convert once per block and copy complete rows into final storage.
- RGB conversion now uses bounded internal tiles and caller-only scatter. Review found the pre-existing RGB worker path contradicted the public provider borrow restriction. The fourth-round prose claiming all caller-output writes were serial was too broad; this checkpoint corrects the implementation without weakening the provider contract.

No public API, precision, signedness, colour transform, fidelity tolerance or external-codec runtime dependency was changed. Resource ceilings remain unchanged; admission now matches the smaller bounded payloads. See [the current migration reservation formulas](../../../../MIGRATION.md), [source/test hashes](checkpoint-f4a05be/qualification.json) and [retained experiments](experiments/INDEX.md). `peakWorkspaceBytes` remains unknown; RSS is not that field.

## Executed validation

| Check | Outcome |
|---|---|
| Full Release | 434 tests / 72 suites, exit 0 |
| Full AddressSanitizer | 434 tests / 72 suites, exit 0 |
| Focused ThreadSanitizer | 50 tests / 10 suites, exit 0 |
| CLI Release and AddressSanitizer | 252 process checks each, exits 0 |
| Lossless independent oracle | 210 profiles in each direction, exact declared point-transform samples |
| DCT independent oracle | 48 profiles in both directions; maximum difference 2, unchanged limits 2/4 for 8/12-bit |
| Seven shared contract hashes | All matched |

[Qualification and source pins](checkpoint-f4a05be/qualification.json), [CLI/oracle commands and exits](checkpoint-f4a05be/cli-oracle-commands.json), [TSan command and exit](checkpoint-f4a05be/tsan-command.json), [ASan log](checkpoint-f4a05be/asan-tests.log). TSan covers the real joined buffer reuse, pipeline-independent grouped reconstruction, RGB caller-output correction and cancellation during provider finalisation. The later experimental pipeline is absent from these counts.

An initial contract hash invocation used the repository root instead of `Documentation/` and could not locate the seven files; its failed receipt is retained separately. The corrected invocation passed. Earlier CI and experimental failures, including rejected performance regressions, remain in [the experiment archive](experiments/INDEX.md).

Native Intel Swift 6.3.3 Debug/Release and strict CLI checks passed at `a4912be` after scoping crash-diagnostic environment variables to library test steps. Its six Apple ARM jobs could not acquire hosted runners; they did not execute tests. Later source CI remains separately tracked, so unavailable simulator/ARM CI is not reported as passed. Physical-device/stable-release gates remain outside this benchmark result.

## Equivalent allocated-output API diagnostic

This supplementary harness compares SwiftJLI with the same pinned libjpeg-turbo **3.2.1** library used by djpeg, within one executable containing both paths. Both retain compressed input and one complete output. Timing includes allocation and decode, excludes output destruction, and uses five warmups, 20 samples and two balanced rounds. RSS uses three paired fresh processes with full output retained. This does **not replace** the whole-process CLI results below.

Full-output quality gates run before timing: exact lossless, maximum difference 2 for 8-bit DCT and 4 for 12-bit DCT. Four RGB/progressive cases exceed the 8-bit threshold (difference 3) and remain excluded in each round. The development-only C shim contains libjpeg error jumps within C and is not a product dependency. Its pinned Homebrew archive targets macOS 27, producing retained linker warnings in the OS 26 diagnostic harness; the executed macOS 27 host is compatible, but this is not OS 26 qualification.

| Case | Workers | Swift ms | Turbo ms | Swift latency reduction | Swift RSS MiB | Turbo RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| flat-19.jpg | 8 | 0.0081 | 0.0119 | +32.5% | 8.77 | 9.22 |
| ramp-19.jpg | 8 | 0.0076 | 0.0111 | +31.7% | 8.73 | 9.22 |
| noise-19.jpg | 8 | 0.0076 | 0.0111 | +31.6% | 8.73 | 9.25 |
| mixed-19.jpg | 8 | 0.0075 | 0.0107 | +29.4% | 8.70 | 9.25 |
| mixed-2048.jpg | 8 | 12.2870 | 18.5205 | +33.7% | 21.28 | 21.77 |
| dct12-512.jpg | 8 | 1.3991 | 1.1206 | -24.9% | 10.17 | 9.33 |
| dct12-2048.jpg | 8 | 18.8978 | 18.5246 | -2.0% | 24.36 | 19.80 |
| dct12-2048.jpg | 1 | 23.3187 | 18.7327 | -24.5% | 20.55 | 19.73 |
| flat-8-512.jpg | 8 | 0.0621 | 0.0766 | +18.9% | 9.05 | 8.80 |
| flat-12-512.jpg | 8 | 0.0719 | 0.1776 | +59.5% | 9.31 | 9.16 |
| noise-8-512.jpg | 8 | 1.3189 | 0.9744 | -35.4% | 9.92 | 9.03 |
| noise-12-512.jpg | 8 | 1.6614 | 1.2373 | -34.3% | 10.28 | 9.50 |

Values are means of round medians; positive reductions mean Swift is faster. All four tiny lossless cases, mixed 2048² and both flat DCT cases are numerically faster in both recorded rounds. Dense DCT remains slower; DCT RSS remains higher. Small lossless and mixed2048 RSS are lower in this owned-output diagnostic. These are provisional observations, not newly accepted controlled wins. [All 105 commands, raw samples and exclusions](checkpoint-f4a05be/owned-output/results.json), [build/tool/compiler hashes](checkpoint-f4a05be/owned-output/build.json).

## Whole-process CLI comparisons

The unchanged harness compares PNM output to `/dev/null`, including process launch, input reads and output. Five warmups, 20 measurements, two balanced rounds, with order rotated per sample. Baseline/candidate output must be exact before timing. RSS is peak process memory from Darwin `time -l`. Separate version batches do not isolate djpeg version effects.

### djpeg 3.2.1 — provisional

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift latency reduction | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 7.528 | 7.609 | 6.118 | -24.4% | 7.36 | 2.81 |
| lossless16 2048² | 21.538 | 21.398 | 26.064 | +17.9% | 19.09 | 2.84 |
| dct12 512² | 8.755 | 8.479 | 6.368 | -33.1% | 7.97 | 2.20 |
| flat 19² | 7.272 | 7.198 | 5.528 | -30.2% | 6.47 | 2.75 |
| flat 512² | 7.250 | 7.187 | 6.261 | -14.8% | 7.08 | 2.81 |
| flat 2048² | 9.771 | 9.716 | 19.367 | +49.8% | 15.03 | 2.84 |
| flat 3072² | 12.803 | 12.685 | 37.088 | +65.8% | 25.66 | 2.84 |
| ramp 19² | 7.440 | 7.387 | 5.735 | -28.8% | 6.47 | 2.75 |
| ramp 512² | 8.723 | 8.656 | 7.188 | -20.4% | 7.28 | 2.81 |
| ramp 2048² | 20.538 | 20.163 | 25.810 | +21.9% | 17.59 | 2.84 |
| ramp 3072² | 34.388 | 33.892 | 48.132 | +29.6% | 30.22 | 2.84 |
| noise 19² | 7.921 | 7.867 | 6.064 | -29.7% | 6.47 | 2.75 |
| noise 512² | 10.441 | 10.533 | 7.592 | -38.7% | 7.53 | 2.81 |
| mixed 19² | 7.926 | 8.029 | 6.083 | -32.0% | 6.47 | 2.75 |
| mixed 512² | 9.277 | 9.195 | 7.618 | -20.7% | 7.36 | 2.81 |
| mixed 2048² | 22.709 | 22.711 | 27.494 | +17.4% | 19.09 | 2.84 |

[Original corpus](checkpoint-f4a05be/cli-original-3.2.1.json) · [Expanded lossless corpus](checkpoint-f4a05be/cli-lossless-patterns-3.2.1.json).

### djpeg 3.2.0 — provisional

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Swift latency reduction | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| lossless16 512² | 8.517 | 8.373 | 6.937 | -20.7% | 7.36 | 2.81 |
| lossless16 2048² | 22.956 | 22.805 | 27.746 | +17.8% | 19.09 | 2.84 |
| dct12 512² | 9.845 | 9.624 | 7.379 | -30.4% | 7.97 | 2.20 |
| flat 19² | 7.496 | 7.462 | 5.523 | -35.1% | 6.47 | 2.73 |
| flat 512² | 7.829 | 8.012 | 6.376 | -25.7% | 7.08 | 2.81 |
| flat 2048² | 10.509 | 10.336 | 17.710 | +41.6% | 15.03 | 2.84 |
| flat 3072² | 13.324 | 13.352 | 31.149 | +57.1% | 25.66 | 2.84 |
| ramp 19² | 8.141 | 7.958 | 6.138 | -29.6% | 6.47 | 2.73 |
| ramp 512² | 9.102 | 9.177 | 7.504 | -22.3% | 7.28 | 2.81 |
| ramp 2048² | 21.072 | 21.185 | 26.606 | +20.4% | 17.59 | 2.84 |
| ramp 3072² | 35.406 | 34.748 | 49.128 | +29.3% | 30.22 | 2.84 |
| noise 19² | 8.353 | 8.499 | 6.317 | -34.5% | 6.47 | 2.73 |
| noise 512² | 11.451 | 11.190 | 8.182 | -36.8% | 7.53 | 2.81 |
| mixed 19² | 8.060 | 8.066 | 6.135 | -31.5% | 6.47 | 2.73 |
| mixed 512² | 9.493 | 9.347 | 7.862 | -18.9% | 7.36 | 2.81 |
| mixed 2048² | 22.993 | 22.833 | 27.324 | +16.4% | 19.09 | 2.84 |

[Original corpus](checkpoint-f4a05be/cli-original-3.2.0.json) · [Expanded lossless corpus](checkpoint-f4a05be/cli-lossless-patterns-3.2.0.json).

The original `lossless16-2048` and expanded `mixed-2048` inputs are byte-identical aliases and must not be counted as two independent wins. RGB/progressive512 remain excluded for difference3>2. Noise2048/3072 and mixed3072 remain excluded because both Swift builds reject them under unchanged CLI defaults. No rejected case is counted as a timing win. All measured CLI RSS cases still favour djpeg, as do small CLI latency and the original512 DCT case.

[Exact benchmark commands and host snapshots](checkpoint-f4a05be/cli-benchmark-commands.json) retain the provisional conditions. The synthetic fixtures and generators retain their earlier [round-two provenance](../DjpegPerformanceRound2_20261102/README.md); no private or clinical data was introduced.

## Remaining work

Dense-image DCT latency, DCT memory and small-process CLI overhead remain competitive gaps. The later [joined pipeline checkpoint](pipeline-14f3501/README.md) records its own exact output, cancellation/lifetime tests and paired API comparisons against this source. No completed goal, universal performance superiority, stable release, physical-device or medical/regulatory claim is made.
