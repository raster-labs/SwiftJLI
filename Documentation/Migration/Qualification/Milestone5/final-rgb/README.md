# Corrected-candidate JPEG oracles — 3 November 2026

**All listed JPEG oracle checks pass at `f548e5048e5c71204c2a2ec4036bf66c4f040285`.** This refresh follows the NativeExecution callback-owner correction, whose source SHA-256 is `695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`. Suite policy stays **0.10.0**, and the original migration predecessor remains `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.

The public consumer/library were built in **Debug** using Apple Swift **6.4.2**, Xcode **27.2**, macOS **27.0.1 ARM64**. The standalone RGB harness uses Swift 6 language mode, complete concurrency checking and a macOS 26.0 deployment target. Own warmed build caches were cloned into fresh scratch; pre-fix receipts and outputs remain unchanged.

| Oracle group | Executed result |
| --- | --- |
| Subsampled RGB | **8 decodes / 16 comparisons**: two pinned sequential/progressive 8-bit 4:2:0 fixtures × scalar/automatic × allocating/padded caller storage, against djpeg **3.2.0 and 3.2.1**. Maximum channel difference **3**, within the existing subsampled limit **3**. |
| Storage/baseline fidelity | Exact allocating/padded outputs and exact candidate/baseline output per backend. Caller allocation identity, five-byte prefix, seven-byte row padding and zero-copy/allocation reports pass. Scalar/automatic output differs by at most **1** channel unit. |
| Independent raw RGB | **16 cases passed** across 8/12-bit sequential/progressive, scalar/automatic and allocating/padded output. Maximum difference **1** at each precision, within existing **2/4** limits. |
| Predictive JPEG | **210 SwiftJLI→djpeg cases and 210 cjpeg→SwiftJLI cases passed**. Covers 2–16-bit precision, predictors 1–7 and declared point transforms, preserving the expected logical samples. |
| DCT JPEG | **48 profiles in both oracle directions passed**; maximum sample difference **2** within unchanged 8/12-bit limits **2/4**. Covers greyscale/4:4:4 RGB, sequential/progressive, scalar/automatic and supported adaptive settings. |

[execution.json](execution.json) records the **19** RGB-runner subprocess commands, all with exit **0**, complete shipping-source hashes, compiler/tool identities, library/harness hashes and the pinned baseline. [Subsampled results](subsampled-results.json) and [raw-RGB results](raw-rgb-results.json) retain every relevant comparison. [Additional oracle commands](additional-oracles.json) record both original script invocations, script/tool hashes and exit **0**; compressed [predictive](lossless-oracles.log.gz) and [DCT](dct-oracles.log.gz) logs preserve their exact output. Generated fixture/output hashes are retained in the corresponding compressed manifests; bulk temporary images remain in scratch.

No source hash changed during these runs. The subsampled fixture pins and generator provenance remain in the [preceding RGB record](../rgb/README.md). The Release baseline is `c7791d5635e46f3ef30f1dd1f14d7189e228a5c0`, compared on the same requested backend. The November benchmark's separate threshold **2** and timing exclusions are unchanged; the subsampled qualification bound **3** predates those benchmarks.

Reproduction uses the maintained [RGB runner](../rgb/run.py) with a fresh `--output` and scratch directory, followed by the unchanged `Scripts/verify-lossless-interop.py` and `Scripts/verify-dct-interop.py`, reusing that oracle build. Exact executed paths are in the receipts. Both additional scripts used explicit cjpeg/djpeg **3.2.1** paths and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Build jobs were limited to two during prebuild; subsequent script runs reused the completed build.

These are finite current-source correctness and public-storage checks. No performance timing, fresh allocator telemetry, Release/other-platform/device qualification or medical claim is implied by this record.
