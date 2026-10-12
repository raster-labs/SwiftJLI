# Migration acceptance ledger — 12 October 2026

**Codec implementation merged; stable-release acceptance remains open.**
[PR #19](https://github.com/raster-labs/SwiftJLI/pull/19) merged on 9 October 2026
as `a967d27bc5756fab8b7fe9db6eb302ff0645c362`. Its tested source revision is
`a1920c7f0ea0ec11009d3d312d680592ac9700e6`; source, tests, package, scripts and
workflow are unchanged in the merge commit. This ledger is the current summary;
STATUS.md retains chronological checkpoints rather than current completion claims.

[CI 37900647193](https://github.com/raster-labs/SwiftJLI/actions/runs/37900647193)
passes all 13 jobs at a1920c7. The separate post-merge main run
[37903247015](https://github.com/raster-labs/SwiftJLI/actions/runs/37903247015)
also passed all 13 jobs at the merge SHA (verified on 12 October).
The original read-only merge audit, reconciled from documentation PR #20, is
[Qualification/MergeAudit.json](Qualification/MergeAudit.json). This follow-up's
revision-bound results are in [Qualification/CompletionAudit.json](Qualification/CompletionAudit.json).

The three maintenance gaps are implemented in draft [PR #21](https://github.com/raster-labs/SwiftJLI/pull/21),
not yet merged. Its codec source is `ba39fda`; `c0c697f` repairs only regression
compilation and the live predecessor comparison. [JPEGDecodeParity.md](JPEGDecodeParity.md)
records the same independent fixtures, scoped source pins, verification and costs.
Full migration acceptance is **not complete**; implementation and successful
finite regressions do not waive the open gates below.

Broad fuzz, memory and oracle qualification retains source `0a714f3` and other
explicitly recorded revisions. `7d85c34` has byte-identical shipping Sources to
0a714f3. The later a1920c7 deadline fix changes NativeExecution.swift;
Qualification/DeadlineOverflow records the original crash, corrected behaviour,
344 Linux release tests and 20 focused benchmark output comparisons. Broad
historical campaigns are not claimed as reruns on the merged revision.

Predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.
Suite policy: 0.10.0. Earlier aa6e298 evidence remains historical and separately
hashed. The UInt12 reader refinement, runtime jobs, fresh URL consumer and
memory experiments have their own source hashes under Qualification.

| Requirement | Evidence / current disposition |
| --- | --- |
| Pinned source, product inventory, licences (POL-05/07; milestone 2) | Passed provenance verifier: 57 principal paths, 56 original source hashes, generated identity fixture and ICC asset/notice. Product dispositions remain in IMPLEMENTATION.md. |
| Independent library and common contract (POL-01–04) | No shipping package dependency. Fresh URL consumer resolves the recorded 7d85c34 baseline and exercises predictive, progressive, float, XYB and explicit colour policies. Actual contents of all 28 shared documents match across four pinned repositories. |
| Public API and ownership (API-01–13; MEM-01–10) | Implemented public codec/storage surface, checked descriptors, leases and bounded operations; covered by API, descriptor, ownership, sample-access, limit and publication tests. This does not make every descriptor layout a codec capability. |
| Native JPEG coverage (milestones 2/4) | SOF3 unsigned 2–16-bit lossless/point-transform, SOF0/1/2 8/12-bit lossy, scale, metadata, explicit float/XYB/RGBA/YCbCr/greyscale policies implemented. MIGRATION.md defines supported combinations and rejection boundaries. |
| Predecessor fidelity (TEST-04/09) | The original 71-record fixture remains intact. PR #21 preserves all encoded identities and 64 decoded identities; seven corrected decoded records match the fixed predecessor v0.5.2. The live comparison runs both pins to cover all records on the same runtime. Historical evidence also includes 71 executed native identity records; 118 public colour-policy comparisons; ordinary and expanded public benchmark cases preserve bytes/samples. Original source pin remains unchanged. |
| Independent JPEG oracles | Retained libjpeg-turbo predictive and DCT bidirectional matrices, and colour interpretation checks. Added licensed libjpeg-turbo source images, six independent 4:4:4 pixel oracles, real embedded ICC preservation and arithmetic rejection tests; nine public decodes match the predecessor. See Qualification/UpstreamCorpus. PR #21 adds 15 unchanged independent chroma fixtures (30 scalar/automatic macOS decodes, maximum error 0–2, limit 3), analytical raw RGB tests and strict padding/budget regressions. These finite matrices are not a universal JPEG conformance claim. |
| Direct source/destination storage (MEM; TEST-09) | Padded/guarded scalar and accelerated matrices; four executed stride/endian mutants; revision-bound Linux encoder 30+30 and decoder 60+60 allocator/control measurements. PR #21 separately checks caller allocation identity, zero hand-off copies and prefix/row padding; its extra component planes are algorithm workspace, not a rerun of the old allocator matrix. See RGBInput and StorageMutations. |
| Cross-codec extension (TEST-03; milestone 3) | SwiftJ2K ↔ SwiftJLI: six 12/16-bit odd/non-square cases, different strides, exact bytes/samples, concurrent readers, sealed mutation rejection, processing-callback cancellation/retry, incompatible endian rejection, 12 independent decodes; separate ASan/TSan runs pass. Linux allocator gives one destination per measured hand-off and exactly one extra with deliberate-copy controls. File tracing sees only final compressed outputs. [Harness](../../Examples/CrossCodecIntegration/README.md). |
| Cross-codec coverage limits | The tested SwiftJLS revision `91092f78b492e332a7ec200e68b76604088e44fb` has contract-only capabilities. Pinned SwiftJ2K rejects HTJ2K. Those pairs cannot be qualified against these revisions. No signed metadata mapping, successful copy-conversion fallback or mid-kernel cross-codec cancellation claim is made by this harness. |
| Full build/test matrix (PLAT-01; TEST-07) | CI [37900647193](https://github.com/raster-labs/SwiftJLI/actions/runs/37900647193) passes all 13 jobs at a1920c7: Linux Swift 6.2/6.4 ARM/x86, independent consumer, common hashes, macOS debug/release/ASan/TSan, native Intel runtime/CLI, nine SDK targets and four simulator suites. The tested source/tests/workflow match merge commit a967d27, whose own 13-job main run also passes. This merged-baseline evidence does not qualify the subsequent PR #21 changes; its current result is tracked in JPEGDecodeParity.md. |
| Local/macOS and Linux CLI foundation (CLI; I3) | 107 process/install/manual checks pass on each host. The minimised Linux image needs its real man-db executable instead of the image's message-only stub; CI setup now handles this. Payload verbs remain explicitly deferred under I3. |
| Fuzzing (TEST-05) | Passed four full one-hour campaigns at 0a714f3: inspect, inspectJPEG, allocating decode and destination decode; all exit 0 with no unresolved crash/hang/bounds finding. See Qualification/FinalFuzz. These campaigns predate the changed JPEG decoder; current-candidate fuzz requalification remains required. The earlier idle-sleep interruption remains a failed historical attempt. |
| Performance (PERF-01–03) | **Open.** FinalPerformance retains two expanded 60-case public runs and two ordinary ten-case runs; all 140 output comparisons pass. Of 120 expanded encode/decode combinations, 44 exceed 5% in both repeats. Required checks, borrowed input handling and worker bounds explain substantial costs; residuals remain. Raw samples, ranges, approximate bootstrap intervals and diagnostic controls are preserved. PR #21 adds an advisory 16–21% 4:2:0 latency increase and higher whole-process RSS; controlled latency and isolated workspace qualification are still required. No blanket waiver or complete performance pass. |
| Memory under failure/cancellation and workspace (PERF-05; TEST-05/09) | Representative qualification passes: 28 Linux stress scopes/controls and 56 Apple scopes/controls, plus refreshed encoder/decoder copy controls. IsolatedMemory retains 120 fresh-process comparisons and 54 attribution controls; async execution and bounded compressed-input materialisation explain the measured memory costs. Workspace reservations and unknown measured peaks are documented explicitly, as permitted by MEM-12 and the common API. These are finite experiments, not exhaustive fault-injection or leak certification. |
| Native Apple runtime matrix (PLAT-01–05; TEST-06) | Native macOS ARM/Intel and iOS/tvOS/visionOS/watchOS simulators pass. Merged-baseline CI passes all four simulator jobs, including the original live iOS predecessor comparison; the earlier 7d85c34 records contain 347 library tests per simulator and 71 matching native identity records. **Physical Watch resource validation remains unexecuted** and cannot be inferred from simulator success. |
| Build-associated SBOMs (PLAT Swift 6.4 qualification) | Swift Build emits SPDX 3.0.1 and CycloneDX 1.7. Independent schema validation passes CycloneDX but rejects two SPDX package records (`externalUrl`, `software_internalVersion`). Raw generated files and failures are preserved; generation is not falsely reported as successful schema validation. |
| Release preparation (milestone 5) | URL consumption, docs, provenance and CLI evidence refreshed. PR #19 is merged. Stable-release acceptance remains open; this task has not published a stable tag, retired the predecessor or performed an application cutover. |

The repository still needs the open performance and physical Watch resource
evidence before an unconditional completion claim. Unavailable external
codec capabilities are explicitly identified rather than replaced by stubs or
runtime oracle fallbacks. The supplied common contracts remain byte-identical.

## Remaining work and completion criteria

| Work | Required evidence or disposition |
| --- | --- |
| Performance acceptance | Repeat the expanded public release matrix on the final release candidate under controlled power/thermal conditions. Resolve or explicitly justify every confirmed regression above the PERF-03 threshold, retaining measured cost, spread, exact output checks and the accepted baseline. The earlier 44 flagged cases are historical results, not a measurement of the deadline-fixed merge. |
| Physical Watch resource validation | Execute a device harness on supported physical Watch hardware with the documented default budgets; record model/OS/revision, memory and latency, boundary/admission failures, repeated work, cancellation and deadline behaviour. Adjust defaults conservatively through a shared-contract revision if necessary; simulator evidence is insufficient. |
| Final release evidence reconciliation | Confirm required evidence covers the chosen release revision, complete the repaired PR #21 CI matrix and current-source fuzzing, refresh affected independent interoperability and memory/workspace controls, and retain the known raw SPDX generator/schema discrepancy rather than claiming validation passed. Stable version/tag publication requires a separate release task. |
| Security release preparation | SECURITY.md requires an established private reporting channel and supported-version policy before the first stable release. On 12 October, GitHub reports private vulnerability reporting disabled and no published releases; an alternative established channel and supported-version policy have not been verified. Repository security settings were not changed. |
| Application adoption / predecessor maintenance | Consumer dependency changes, deployment-floor changes, fixture acceptance, rollback and predecessor maintenance announcements are separate work; no application repository was cut over by PR #19. |

`JLIDICOM` and `JLIBench` remain deferred products under I1/I2; their required
fixture obligations are accounted for by provenance. CLI encode/decode/inspect/
validate payload commands remain separate new work under I3. Unsupported codec
profiles and unavailable cross-codec pairs remain capability limits, not completed
features. They must not be converted into an unqualified “all migration done” claim.
