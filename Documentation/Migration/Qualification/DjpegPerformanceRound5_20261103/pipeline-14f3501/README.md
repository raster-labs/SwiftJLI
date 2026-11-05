# Joined pipeline checkpoint — 14f3501, 3 November 2026

**The overall djpeg goal remains open.** This checkpoint records the integrated bounded greyscale pipeline and its completed local checks. Timings remain provisional under unrelated host activity. The [f4 checkpoint](../README.md#retained-f4a05be-checkpoint) retains its own results; counts and measurements from the two revisions are not pooled.

The tested source is `704ddae1bafea95d8a48c01ce35887c5b6413c0d`, integrated as `fe5d267bcc2e7d45f397aa648c1c14ea3da85226` and documented at `14f35018d241666358480da2a8527d29ab047627`. An independent comparison of all 51 files under `Sources/` found only documentation-comment differences in `SequentialGreyscalePlan.swift`; the test trees have no diff. See [all source hashes](source-pins.json) and [the complete difference](tested-to-root-source.patch). Native comparisons use `f4a05be9f3003a48adaa840abd48fcf6071f009d` as baseline.

Suite policy **0.10.0**, Apple OS **26.0** floor, Swift **6.2** manifest minimum and Swift **6.4** primary toolchain are unchanged. The executed host used Apple Swift **6.4.2**, Xcode **27.2**, macOS **27.0.1**, M4 Max, 16 cores and 64 GiB RAM.

## Behaviour, memory and ownership

For eligible full-scale, sequential, one-component 8/12-bit scans with at least 2,048 blocks, accelerated decoding and a worker ceiling of at least two, the caller now decodes entropy while one worker reconstructs the preceding canonical 1,024-block group. Two 256 KiB coefficient/output slots alternate around one 256 KiB Float scratch slot: **768 KiB** of bounded payload. Compact table-proven DC scans retain their separate 8 KiB path. Explicit one-worker and scalar paths retain their selected serial/grouped behaviour.

The shared plan selects the same payload for admission and dispatch. For large accelerated scans, the payload falls from the f4 grouped maximum of 4 MiB to 768 KiB; at the 512² selection boundary it increases from the previous 512 KiB serial payload to permit overlap. These are allocation payloads, not measured process peaks. Resource ceilings and sample format remain unchanged; `peakWorkspaceBytes` remains unknown.

Only the caller reads compressed input and writes provider storage. The worker receives disjoint internal storage plus immutable quantisers, then publishes completion before caller scatter and slot reuse. The final correction joins the **complete submitted work item** on every return and throw before any owning-array borrow ends. The earlier internal completion signal alone was not used as proof that the work item had returned. Cancellation is polled at bounded entropy-row and transform boundaries and while waiting for completion.

The [pipeline](../../../../../Sources/SwiftJLI/Native/Decoder/PipelinedGreyscaleDecoder.swift), [shared plan](../../../../../Sources/SwiftJLI/Native/Decoder/SequentialGreyscalePlan.swift) and [lifetime/cancellation tests](../../../../../Tests/SwiftJLITests/Native/PipelinedGreyscaleTests.swift) preserve resolution, precision, Float batch shapes, sample conversion, restart/stuffing behaviour and the public caller-storage contract. No public API, fidelity tolerance, implicit display conversion, disk spill or external-codec runtime dependency was introduced.

## Executed validation and boundaries

| Check | Result at the tested pipeline source |
|---|---|
| Full Release | 436 tests / 73 suites, exit 0 |
| Focused AddressSanitizer | 26 tests / 5 suites, exit 0 |
| Focused ThreadSanitizer | 26 tests / 5 suites, exit 0 |
| CLI Release and AddressSanitizer | 252 process checks each, exit 0 |
| DCT independent oracle | 48 profiles in each direction; maximum sample difference 2 |
| Native DCT comparison | 12 fixtures × 2 rounds, every full-output SHA-256 and byte count exact |
| Owned-output API diagnostic | 105 child commands, all exit 0; 24 accepted timing records, 8 quality exclusions, 72 fresh-process RSS observations |

[Qualification receipt](qualification.json), [full Release log](full-release-tests.log), [sanitizer commands and exits](sanitizer-commands.json), [ASan log](address-tests.log), [TSan log](thread-tests.log), [CLI/oracle commands and exits](cli-oracle-commands.json), [Release CLI report](release-cli/report.json), [ASan CLI report](asan-cli/report.json), [DCT oracle log](dct-oracle.log).

The focused sanitizer groups cover pipeline success, producer cancellation, worker failure, joined reuse, workspace admission and provider-finalisation cancellation. These are **not full-suite sanitizer counts**. The earlier f4 full ASan and lossless-oracle results remain attached to f4; neither was rerun in full here. Whole-process CLI performance was also not rerun for this checkpoint. The initial `69aa3d2` focused gate and native matrix are retained separately in [pipeline-initial](../experiments/pipeline-initial); they are superseded for final lifetime qualification by the joined source.

The [completed f4 CI snapshot](ci-f4-complete.json) for run `41653197075` records seven successful jobs: Intel native tests/CLI, four Linux Swift 6.2/6.4 architecture jobs, shared-contract identity and the tools-6.2 consumer. Six Apple ARM jobs were cancelled with no executed steps; the overall workflow conclusion is failure. They are unavailable gates, not executed test failures or passes. This compact snapshot does not contain runner annotations, so it does not independently establish the scheduling cause. CI for `14f3501` (run `41657375246`) was initially queued. The [later completed snapshot](ci-14f-latest.json) records **four executed Linux failures**, three successful jobs (Intel, contract and consumer), and six Apple ARM cancellations without steps. The [failure extract](ci-14f-failure-extract.txt) and [diagnosis](ci-14f-summary.json) preserve the same synthetic NaN worker-failure test issue on all four Linux jobs: scalar clipping can produce a finite sample instead of forcing the intended error. This does not establish valid-JPEG sample divergence, but the failed test remains a failed gate. The subsequent [test-only correction](../experiments/ci-worker-failure/qualification.json) uses an unsupported internal three-byte layout to force the existing worker guard on both backends. It passed locally at child `396ddd1` (2 tests/1 suite, six parameter cases), integrated as `fd6e1a1` with unchanged production sources; see [the exact equivalence receipt](../experiments/ci-worker-failure/source-equivalence.json). No corrected remote pass is claimed. Physical-device and stable-release gates remain unexecuted here.

## Native latency against f4

The existing release harness retains five warmups and 20 measured decodes per fixture in each of two balanced rounds. Negative change means faster. These timings exclude output destruction and must not be pooled with tiny batched measurements that include release.

| Fixture | Round 1 latency change | Round 2 latency change |
|---|---:|---:|
| dct12-512.jpg | -12.88% | -5.69% |
| dct12-2048.jpg | -4.91% | -10.20% |
| rgb8-512.jpg | -0.37% | +0.96% |
| rgb8-2048.jpg | -0.62% | -0.12% |
| progressiveRGB8-512.jpg | -6.55% | -1.32% |
| progressiveRGB8-2048.jpg | -1.20% | -1.02% |
| xyb8-512.jpg | +1.06% | -4.64% |
| xyb8-2048.jpg | +3.90% | +1.48% |
| flat-8-512.jpg | -5.10% | -1.86% |
| flat-12-512.jpg | +16.30% | +0.80% |
| noise-8-512.jpg | -15.14% | -10.72% |
| noise-12-512.jpg | -6.65% | -9.30% |

[Raw joined matrix and command/object/fixture hashes](joined-native.json), [derived arithmetic](derived-results.json), [unchanged harness](../experiments/harnesses/swiftjli-round2-dct-benchmark.swift).

The targeted dense greyscale cases improve in both rounds. The flat12-512 outlier (+16.30% in round one) and the smaller repeated XYB2048 slowdowns remain visible; broad non-regression is not established. No result is attributed solely to pipelining merely because it changed between runs.

## Equivalent allocated-output API comparison

The development-only comparator links SwiftJLI and the pinned libjpeg-turbo **3.2.1** static library in one executable. Both retain compressed input and a complete output, include output allocation through decoder completion in timing, and release output outside the timed region. Five warmups, 20 samples and two balanced rounds are retained; RSS is the median of three paired fresh processes. This comparison does **not replace djpeg CLI measurements**, where the reference can stream rows.

Full-output quality gates precede timing: exact lossless samples, maximum difference 2 for 8-bit DCT and 4 for 12-bit DCT. Four RGB/progressive cases have maximum difference 3 and remain excluded in both rounds. All included DCT comparisons here have maximum difference at most 1. The C shim contains its error jumps entirely within C; it is not a shipping dependency.

| Case | Workers | Swift ms | Turbo ms | Swift latency reduction | Swift RSS MiB | Turbo RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| flat-19.jpg | 8 | 0.0072 | 0.0104 | +30.6% | 8.75 | 9.25 |
| ramp-19.jpg | 8 | 0.0081 | 0.0115 | +29.5% | 8.77 | 9.28 |
| noise-19.jpg | 8 | 0.0087 | 0.0115 | +24.1% | 8.77 | 9.27 |
| mixed-19.jpg | 8 | 0.0076 | 0.0108 | +29.6% | 8.80 | 9.25 |
| mixed-2048.jpg | 8 | 12.2822 | 18.4711 | +33.5% | 21.33 | 21.77 |
| dct12-512.jpg | 8 | 1.3756 | 1.2858 | -7.0% | 10.56 | 9.38 |
| dct12-2048.jpg | 8 | 18.4389 | 19.1385 | +3.7% | 21.02 | 19.81 |
| dct12-2048.jpg | 1 | 24.8627 | 19.8898 | -25.0% | 20.62 | 19.81 |
| flat-8-512.jpg | 8 | 0.0639 | 0.0758 | +15.6% | 9.08 | 8.83 |
| flat-12-512.jpg | 8 | 0.0767 | 0.1852 | +58.6% | 9.33 | 9.17 |
| noise-8-512.jpg | 8 | 1.2609 | 1.1288 | -11.7% | 10.28 | 9.00 |
| noise-12-512.jpg | 8 | 1.6358 | 1.4333 | -14.1% | 10.69 | 9.48 |

Times are means of round medians; positive reductions mean faster. Tiny lossless, mixed2048, flat DCT and worker-ceiling-8 DCT12-2048 are numerically faster in both recorded rounds. For DCT12-2048 the reductions are only **2.69% and 4.57%**, not a controlled material win. Its RSS remains **21.016 MiB versus 19.813 MiB**. Worker-ceiling-1 DCT, dense 512² DCT, all listed DCT RSS cases and the previously measured small CLI cases remain gaps.

[All raw samples, exclusions, RSS and host snapshots](owned-output/results.json), [compiler/object/library/source hashes and build commands](owned-output/build.json), [comparator source](owned-output/Compare.swift), [C shim](owned-output/jpeg_bench.c). The pinned Homebrew static archive targets macOS 27 and emitted retained warnings when linked into the OS 26 diagnostic harness. Execution on macOS 27.0.1 does not qualify OS 26 or change the product floor. No separate sanitizer or cross-platform qualification of this development-only shim is claimed.

Host snapshots record active VM and WindowServer work, with a Java process above 500% CPU after the run; thermal state is also recorded per result. These limitations prevent treating the timings as controlled wins. The fixed quality gates and excluded records remain unchanged.

## Rejected follow-up trials and remaining work

[SIMD coefficient packing](../experiments/simd-pack/decision.json) preserved packed Float bits and every fixture output, but produced no repeatable material gain; it was rejected. [Paired AC decoding](../experiments/ac-pairs/decision.json) passed 20 tests/6 suites and all 12 fixture outputs in both rounds, but repeatedly regressed dense 12-bit DCT by about 12–19%; it was rejected. Its initial test-macro compile failure and subsequent test-only correction are both retained. Neither trial is part of this pipeline checkpoint.

Small CLI launch overhead, dense DCT latency and memory remain open. The [historical f4 whole-process comparisons](../README.md#whole-process-cli-comparisons) retain the exact source, aliases, quality exclusions and resource-admission exclusions under which they were measured. No latest-source CLI win is inferred from those earlier numbers.

Fixture provenance remains the earlier [round-two record](../../DjpegPerformanceRound2_20261102/README.md) and the hashes in each raw matrix. No private or clinical data was introduced. Run [the report verifier](../verify_report.py) to validate archived byte counts, hashes and JSON without building or benchmarking.
