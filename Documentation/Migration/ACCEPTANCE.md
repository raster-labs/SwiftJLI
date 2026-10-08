# Migration acceptance ledger — 8 October 2026

**The migration is not yet fully accepted.** This ledger is the current summary;
STATUS.md retains chronological checkpoints, whose old pending statements and
earlier implementation descriptions do not override this table.

Shipping source: `0a714f32a2ef5e1b8be48f6b02500e43833489d2`.
Qualification workflow/harness revision: `7d85c34af5d70ae931eeb0bd87b79099f0bb774b`;
its shipping Sources are byte-identical to 0a714f3.
Predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.
Suite policy: 0.10.0. Earlier aa6e298 evidence remains historical and separately
hashed. The UInt12 reader refinement, runtime jobs, fresh URL consumer and
memory experiments have their own source hashes under Qualification.

| Requirement | Evidence / current disposition |
| --- | --- |
| Pinned source, product inventory, licences (POL-05/07; milestone 2) | Passed provenance verifier: 57 principal paths, 56 original source hashes, generated identity fixture and ICC asset/notice. Product dispositions remain in IMPLEMENTATION.md. |
| Independent library and common contract (POL-01–04) | No shipping package dependency. Fresh URL consumer resolves 7d85c34 with the exact shipping source and exercises predictive, progressive, float, XYB and explicit colour policies. Actual contents of all 28 shared documents match across four pinned repositories. |
| Public API and ownership (API-01–13; MEM-01–10) | Implemented public codec/storage surface, checked descriptors, leases and bounded operations; covered by API, descriptor, ownership, sample-access, limit and publication tests. This does not make every descriptor layout a codec capability. |
| Native JPEG coverage (milestones 2/4) | SOF3 unsigned 2–16-bit lossless/point-transform, SOF0/1/2 8/12-bit lossy, scale, metadata, explicit float/XYB/RGBA/YCbCr/greyscale policies implemented. MIGRATION.md defines supported combinations and rejection boundaries. |
| Predecessor fidelity (TEST-04/09) | 71 executed native identity records; 118 public colour-policy comparisons; ordinary and expanded public benchmark cases preserve bytes/samples. Original source pin remains unchanged. |
| Independent JPEG oracles | Retained libjpeg-turbo predictive and DCT bidirectional matrices, and colour interpretation checks. Added licensed libjpeg-turbo source images, six independent 4:4:4 pixel oracles, real embedded ICC preservation and arithmetic rejection tests; nine public decodes match the predecessor. See Qualification/UpstreamCorpus. These finite matrices are not a universal JPEG conformance claim. |
| Direct source/destination storage (MEM; TEST-09) | Padded/guarded scalar and accelerated matrices; four executed stride/endian mutants; current-source Linux encoder 30+30 and decoder 60+60 allocator/control measurements. See RGBInput and StorageMutations. |
| Cross-codec extension (TEST-03; milestone 3) | SwiftJ2K ↔ SwiftJLI: six 12/16-bit odd/non-square cases, different strides, exact bytes/samples, concurrent readers, sealed mutation rejection, processing-callback cancellation/retry, incompatible endian rejection, 12 independent decodes; separate ASan/TSan runs pass. Linux allocator gives one destination per measured hand-off and exactly one extra with deliberate-copy controls. File tracing sees only final compressed outputs. [Harness](../../Examples/CrossCodecIntegration/README.md). |
| Cross-codec coverage limits | Current SwiftJLS main `91092f78b492e332a7ec200e68b76604088e44fb` has contract-only capabilities. Pinned SwiftJ2K rejects HTJ2K. Those pairs cannot be qualified against these revisions. No signed metadata mapping, successful copy-conversion fallback or mid-kernel cross-codec cancellation claim is made by this harness. |
| Full build/test matrix (PLAT-01; TEST-07) | CI [37772189185](https://github.com/raster-labs/SwiftJLI/actions/runs/37772189185) passes all 13 jobs at 7d85c34: Linux Swift 6.2/6.4 ARM/x86, independent consumer, common hashes, macOS debug/release/ASan/TSan, native Intel runtime/CLI, nine SDK targets and four simulator suites. Shipping source is byte-identical to 0a714f3. |
| Local/macOS and Linux CLI foundation (CLI; I3) | 107 process/install/manual checks pass on each host. The minimised Linux image needs its real man-db executable instead of the image's message-only stub; CI setup now handles this. Payload verbs remain explicitly deferred under I3. |
| Fuzzing (TEST-05) | Passed four full one-hour campaigns at 0a714f3: inspect, inspectJPEG, allocating decode and destination decode; all exit 0 with no unresolved crash/hang/bounds finding. See Qualification/FinalFuzz. The earlier idle-sleep interruption remains a failed historical attempt. |
| Performance (PERF-01–03) | **Open.** FinalPerformance retains two expanded 60-case public runs and two ordinary ten-case runs; all 140 output comparisons pass. Of 120 expanded encode/decode combinations, 44 exceed 5% in both repeats. Required checks, borrowed input handling and worker bounds explain substantial costs; residuals remain. Raw samples, ranges, approximate bootstrap intervals and diagnostic controls are preserved. No blanket waiver or complete performance pass. |
| Memory under failure/cancellation and workspace (PERF-05; TEST-05/09) | Representative qualification passes: 28 Linux stress scopes/controls and 56 Apple scopes/controls, plus refreshed encoder/decoder copy controls. IsolatedMemory retains 120 fresh-process comparisons and 54 attribution controls; async execution and bounded compressed-input materialisation explain the measured memory costs. Workspace reservations and unknown measured peaks are documented explicitly, as permitted by MEM-12 and the common API. These are finite experiments, not exhaustive fault-injection or leak certification. |
| Native Apple runtime matrix (PLAT-01–05; TEST-06) | Native macOS ARM/Intel and iOS/tvOS/visionOS/watchOS simulators pass. Each simulator passes 347 tests; all 71 native identity records match the actual predecessor on iOS. **Physical Watch resource validation remains unexecuted** and cannot be inferred from simulator success. |
| Build-associated SBOMs (PLAT Swift 6.4 qualification) | Swift Build emits SPDX 3.0.1 and CycloneDX 1.7. Independent schema validation passes CycloneDX but rejects two SPDX package records (`externalUrl`, `software_internalVersion`). Raw generated files and failures are preserved; generation is not falsely reported as successful schema validation. |
| Release preparation (milestone 5) | URL consumption, docs, provenance and CLI evidence refreshed. Complete acceptance/review remains open. Stable tag, merge, predecessor retirement and application cutover are separate actions; none has occurred. |

The repository still needs the open performance and physical Watch resource
evidence before an unconditional completion claim. Unavailable external
codec capabilities are explicitly identified rather than replaced by stubs or
runtime oracle fallbacks. The supplied common contracts remain byte-identical.
