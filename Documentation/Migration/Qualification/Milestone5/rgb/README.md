# Milestone 5 RGB acceptance — 3 November 2026

**The two subsampled benchmark fixtures pass the existing profile-specific RGB limit of 3. Their stricter benchmark limit of 2 and historical timing exclusions remain unchanged.** No shipping source or fidelity threshold changed.

Candidate: `8ae2762710d6279cd92222f5bb5ca95f042f694e`; original codec migration predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`; suite policy **0.10.0**. The checked shipping-source manifest remained unchanged during these runs. Candidate library and oracle consumer were built in **Debug**, with Apple Swift **6.4.2**, Xcode **27.2 (27B52)**, on macOS **27.0.1 ARM64**. The standalone harness uses Swift 6 mode, complete concurrency checking and a macOS 26.0 deployment target. This is current-source local correctness evidence, not a Release build, other-platform qualification or performance measurement.

## Scope and results

| Check | Executed result |
| --- | --- |
| Subsampled RGB | Two 512 × 512, 8-bit 4:2:0 fixtures: sequential and progressive. Scalar/automatic × allocating/padded caller storage gives **8 decodes**. Comparison with pinned djpeg **3.2.0 and 3.2.1** gives **16 comparisons**, each with maximum RGB channel difference **3**, within the established limit **3**. |
| Baseline fidelity | Every candidate output exactly matches the Release baseline `c7791d5635e46f3ef30f1dd1f14d7189e228a5c0` on the **same backend**, including complete PNM bytes. Sequential/progressive output agrees. Scalar versus automatic differs by at most **1** channel unit; both satisfy the independent oracle bound. |
| Caller storage | Allocating/padded outputs agree exactly per backend; caller allocation identity, five-byte prefix and seven-byte row padding are preserved. Reports contain zero caller-path pixel allocations and no copy events. These are public API/report and sample checks, not new allocator telemetry. |
| Independent raw RGB | Existing `Scripts/verify-raw-rgb-interop.py` passes **16 cases**: 8/12-bit × sequential/progressive × scalar/automatic × allocating/padded storage. Observed maximum difference is **1** at each precision, within the existing **2/4** limits. Uses libjpeg-turbo **3.2.1**. |
| Commands | Final runner and all **19** recorded subprocess commands exit **0**. No benchmark timings were taken. |

Exact commands, source and tool hashes, compiler identity and exit results are in [execution.json](execution.json). Per-case results are in [subsampled-results.json](subsampled-results.json) and [raw-rgb-results.json](raw-rgb-results.json). The latter also retains every original raw-RGB script command and fixture/output hash.

The established subsampled limit comes from [`JPEGDecodeParityTests.independentChroma`](../../../../../Tests/SwiftJLITests/JPEGDecodeParityTests.swift), introduced at `ba39fda` on 12 October 2026 with `maximum <= 3`; its [qualification record](../../../JPEGDecodeParity.md) explicitly records that unchanged limit. The separate 4:4:4 DCT oracle retains its tighter 8-bit limit of 2. `Scripts/benchmark-djpeg.py` independently chose 2 for these 4:2:0 timing fixtures. Meeting the older subsampled qualification bound does not retroactively accept those benchmark timings.

## Reproduction and provenance

The two retained JPEGs under [fixtures](fixtures/) are synthetic in-house fixtures from the [original fixture harness](../../DjpegPerformance20261102/original-fixture-harness.swift), encoded using JLISwift `b6df774a3c3ecdf4b98971f31543fdd18074ace2` / v0.6.0. Their source formula, sampling and progression settings are retained there. They contain no patient data or newly relicensed third-party material.

| Fixture | SHA-256 |
| --- | --- |
| `rgb8-512.jpg` | `e076975035045954e167a47065e9a139f0b2ff464fc1e0387ac0b205305fe55c` |
| `progressiveRGB8-512.jpg` | `050be0da3209a4515ac90b45afe0d419e5e99e28c1339d6e25d64a7ffcc3f20b` |

Run from the repository root, with a fresh scratch directory. The baseline argument must be the previously pinned binary whose SHA-256 is checked by the runner; build an equivalent pinned baseline if that binary is unavailable, then explicitly update the reproduction pin and record the compiler/build provenance rather than bypassing the check.

```sh
python3 Documentation/Migration/Qualification/Milestone5/rgb/run.py \
  --fixtures Documentation/Migration/Qualification/Milestone5/rgb/fixtures \
  --scratch /private/tmp/swiftjli-m5-rgb-reproduction \
  --djpeg-320 /opt/homebrew/Cellar/jpeg-turbo/3.2.0/bin/djpeg \
  --djpeg-321 /opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg \
  --baseline-cli /private/tmp/swiftjli-round2-final-build/out/Products/Release/swiftjli-cli
```

The runner prebuilds the existing oracle consumer with two jobs, links the [subsampled harness](subsampled.swift) to that same library object, and reuses the build for the raw-RGB script. Exact executed paths appear in the receipt; retained fixture copies have identical hashes. Temporary reference PNM files are deliberate test artefacts, not codec image spilling.

## Initial harness correction

The [initial receipt](initial-debug-execution.json) and [failure log](initial-debug-subampled.log) retain a failed harness assumption: one historical **automatic-backend** PNM hash was incorrectly asserted for the scalar decode too. The pinned baseline itself has distinct scalar (`45097e53…`) and automatic (`cc7548e9…`) hashes with identical PNM headers. The harness was corrected to compare candidate/baseline per backend and to report scalar/automatic differences separately. The final runs above passed; no codec change was made to obtain that result. The initial top-level thrown harness error exited by signal 5; the corrected harness reports errors with exit 1.

Physical-device, platform-matrix, security-reporting and other Milestone 5 gates remain separate. This finite profile check makes no medical, regulatory or universal decoder-conformance claim.
