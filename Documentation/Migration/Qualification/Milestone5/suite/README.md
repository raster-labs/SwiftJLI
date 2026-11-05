# Milestone 5 four-codec handoff qualification — 3 November 2026

**The pre-fix snapshot passes 72 ordinary handoffs, 72 deliberate-copy controls and 72 independent output decodes.** This record is pinned to shipping source equivalent to `8ae2762`, before the subsequent NativeExecution callback-owner correction. Later shipping changes require their own qualification; these results must not be relabelled as runs of that correction.

The successful run records repository revision `f4e6e6562b32056affbb375f8cd6bb708bc7d8ad`. Its shipping and harness source hashes exactly match the initial `8ae2762710d6279cd92222f5bb5ca95f042f694e` manifest. [The frozen pre-fix snapshot](pre-fix-snapshot.json) retains that comparison and rechecked executable hash. Original SwiftJLI migration provenance remains JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`; suite policy is **0.10.0**.

| Component | Immutable revision |
| --- | --- |
| SwiftJ2K | `be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748` |
| SwiftJLS | `f481f6031279b8ca5c51f559df33cc66a9e4e06b` |
| SwiftJXL | `253424054d4cc7f903ed51dcf83702b099b204dd` |

The existing [development harness](../../../../../Examples/SuitePairIntegration/README.md) and its package manifest were used unchanged. Dependencies resolve at those exact pins; no shipping dependency was added.

## Executed evidence

| Check | Result |
| --- | --- |
| Ordinary Linux Release build | Swift **6.4.2**, `aarch64-unknown-linux-gnu`, two build jobs; exit **0**. Base image `sha256:bca121f6eb59fd80340d1296887b2698ed8f3eb9eca7d80c181f8af769dc7ee0`. |
| All ordered codec pairs | **72 handoffs**: all twelve ordered pairs × 19×13, 65×31 and 257×17 × 12/16 meaningful bits. Exact logical samples and destination codestream bytes; different source/destination strides; concurrent readers; caller owner identity; padding and sealed-mutation rejection. Exit **0**. |
| Cancellation and rejection | Existing harness checks each codec's callback encode/decode cancellation, destination reuse after pre-write cancellation and dimension mismatch under both copy policies. These are not mid-kernel cancellation claims. |
| Heap controls | **72 ordinary measurements + 72 deliberate-copy controls** pass `verify-cross-codec-heap.py --suite`. Each ordinary measurement has one final-destination-sized allocation; the injected copy adds exactly one. Allocator calibration is included; no sanitizer figures are used. Exit **0**. |
| Independent decodes | All **72 published outputs** decode with the appropriate independent oracle, preserving geometry, precision and every original logical sample. Original script and its **74 subprocess commands** exit **0**. |
| Baseline/control identity | All **72 compressed files** have identical SHA-256 values between ordinary and deliberate-copy runs. |

Commands, source/binary hashes, exact resolved peer pins and output hashes are in [final/execution.json](final/execution.json). That directory name identifies this attempt's completed run, not a post-fix release candidate. Stdout/stderr stay separate. The [heap verifier output](final/heap-verification.stdout.log) and [independent oracle receipt](oracles/execution.json) are concise summaries; [per-file oracle results](oracles/results.json) retain every command, outcome and input/output hash.

These allocation histograms detect the tested final-image allocation shape, not every possible copy instruction. Algorithm workspace remains permitted. SwiftJXL's public allocation counters remain unknown; the external heap controls supply the tested allocation evidence. No new timing benchmark, ASan/TSan suite run or file/process tracing was performed in this scoped refresh.

## Independent oracle environment

An isolated development image was built using [Oracle.Dockerfile](Oracle.Dockerfile). Nothing was installed globally or added to a shipped Swift target. [Image provenance](oracle-image.json) records the immutable base, resulting image ID, Dockerfile/CharLS-helper hashes and host oracle binaries; [the package manifest](oracle-packages.log) records all installed versions.

| Oracle | Recorded version |
| --- | --- |
| libjpeg-turbo, host `djpeg` | **3.2.1**, build 20261026 |
| OpenJPEG, host `opj_decompress` | **2.5.4** |
| CharLS, isolated image | **2.4.2-2build2** |
| libjxl / `djxl`, isolated image | **0.7.0-10.2ubuntu6.1** |
| GNU C++ metapackage | **4:13.2.0-7ubuntu1**; installed compiler **13.3.0-6ubuntu2~24.04.1** |

The oracle image is `sha256:4fbd66df9d932895597c4dfa93bfa0b8823350bd70754416548ceb8f3dada60b`. Oracle runtime containers have networking disabled and receive already-published compressed outputs. libjxl's 12-bit PGM output uses normalised UInt16 representation; observed rounding error is at most one UInt16 unit and every value inverts exactly to the original 12-bit integer. This is an independently checked oracle representation conversion, not permitted codec sample loss.

## Reproduction and retained setup failures

Use fresh scratch and evidence paths. The maintained runners reject an existing `--output` directory before writing logs, preserving prior qualification. Source and harness paths remain anchored to their script directories.

```sh
python3 Documentation/Migration/Qualification/Milestone5/suite/run.py \
  --scratch "$PWD/.build-m5-suite-reproduction" \
  --output /private/tmp/swiftjli-m5-suite-reproduction-evidence
python3 Documentation/Migration/Qualification/Milestone5/suite/build-oracle-image.py \
  --output /private/tmp/swiftjli-m5-suite-reproduction-image-evidence
python3 Scripts/verify-suite-outputs.py \
  --input "$PWD/.build-m5-suite-reproduction/normal" \
  --output "$PWD/.build-m5-suite-reproduction/oracles" \
  --oracle-image swiftjli-m5-oracles:20261103
```

On this host, Colima shares `/Users` but does not share host `/private/tmp` with the Docker VM. The [initial receipt](execution.json) records a successful Linux build followed by a host-side missing-binary error under `/private/tmp`; no codec execution had failed. Only this task's own cache was copied from that VM path into the ignored `.build-m5-suite` scratch directory, with the same `/work` container mapping. The resumed build and all checks then passed. The original executed setup runner is retained as [run-initial.py](run-initial.py).

The completed image receipt predates the output-directory guard; its exact executed runner is [build-oracle-image-executed.py](build-oracle-image-executed.py). [Output-path refinement checks](output-path-refinement.json) verify all three RGB/suite/image runners refuse existing evidence and configure fresh output independently, while the completed receipts remain byte-identical. Fresh-path checks intercept subprocess execution before any codec command; no completed codec results were repeated for that path-only change.

The common suite profile remains unsigned greyscale lossless JPEG, Part 1 JPEG 2000, JPEG-LS and Modular JPEG XL. HTJ2K, signed interpretation, multiframe, successful layout-conversion fallback, coefficient/reconstruction transcoding and physical-device qualification remain outside this finite harness scope.
