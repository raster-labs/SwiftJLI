# Corrected-candidate suite qualification — 3 November 2026

**All 72 handoffs, 72 deliberate-copy controls and 72 independent output decodes pass at `f548e5048e5c71204c2a2ec4036bf66c4f040285`.** The only changed shipping/harness file relative to the [pre-fix snapshot](../suite/pre-fix-snapshot.json) is `Sources/SwiftJLI/NativeExecution.swift`, SHA-256 `695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`. Suite policy remains **0.10.0**.

The unchanged development harness resolves SwiftJ2K `be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`, SwiftJLS `f481f6031279b8ca5c51f559df33cc66a9e4e06b` and SwiftJXL `253424054d4cc7f903ed51dcf83702b099b204dd`. SwiftJLI's original migration predecessor remains `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.

| Gate | Executed result |
| --- | --- |
| Ordinary Linux Release build | Swift **6.4.2**, ARM64, two build jobs, exit **0**. Own warmed caches were cloned into fresh ignored `.build-m5-final-suite`; pre-fix evidence and outputs remain intact. |
| Shared-storage handoffs | **72 passed**, covering all twelve ordered pairs across three odd/non-square geometries and 12/16-bit precision. Exact samples and codestreams, different strides, concurrent readers, caller allocation identity, padding, sealing, callback cancellation/retry and dimension rejection checks pass. |
| Allocation controls | **72 ordinary + 72 deliberate-copy measurements passed**. One final-destination-sized allocation normally; exactly one additional allocation with the injected copy. No sanitizer allocation figures are used. |
| Independent interoperability | **72 decodes passed**, preserving geometry, meaningful precision and every original logical sample. Uses djpeg **3.2.1**, OpenJPEG **2.5.4**, CharLS **2.4.2-2build2** and libjxl **0.7.0-10.2ubuntu6.1**. |
| Output identity | All **72 compressed outputs** are byte-identical between ordinary/control runs. Source/harness hashes remained unchanged throughout the run. |

[execution.json](execution.json) contains the exact **11** runner subprocess commands, all with exit **0**, compiler/container identities, source and resolved-peer hashes, executable hash, and both output hash manifests. [Heap-verification output](heap-verification.stdout.log) records the allocation-control result. [Oracle execution](oracles/execution.json) and [per-file results](oracles/results.json) retain the additional independent script command and its **74** successful subprocesses.

The build image is pinned to `sha256:bca121f6eb59fd80340d1296887b2698ed8f3eb9eca7d80c181f8af769dc7ee0`; the independent oracle image is pinned to `sha256:4fbd66df9d932895597c4dfa93bfa0b8823350bd70754416548ceb8f3dada60b`. [Oracle image/package provenance](../suite/oracle-image.json) remains unchanged. Runtime oracle containers have networking disabled. libjxl's 12-bit normalised UInt16 representation differs by at most one UInt16 unit, then inverts exactly to each original 12-bit sample.

To reproduce, use the maintained [suite runner](../suite/run.py) with new scratch/output directories and then `Scripts/verify-suite-outputs.py` with a fresh oracle output directory; the commands and Colima shared-directory requirement are documented in [the preceding suite record](../suite/README.md). The executed command here was:

```sh
python3 Documentation/Migration/Qualification/Milestone5/suite/run.py \
  --scratch /Users/pushparaj/projects/SwiftJLI-milestone5/.build-m5-final-suite \
  --output /Users/pushparaj/projects/SwiftJLI-milestone5/Documentation/Migration/Qualification/Milestone5/final-suite
```

Those directories now exist; choose new names when reproducing. The runner rejects an existing evidence output directory.

This finite profile is unsigned greyscale lossless JPEG, Part 1 JPEG 2000, JPEG-LS and Modular JPEG XL. No new benchmark, suite ASan/TSan run, file/process trace, physical-device qualification or unsupported-profile claim is inferred. SwiftJXL allocation reports remain unknown; independent telemetry supplies the tested handoff evidence.
