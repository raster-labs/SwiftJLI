# Migration acceptance ledger — 8 October 2026

**The migration is not yet fully accepted.** This ledger is the current summary;
STATUS.md retains chronological checkpoints, whose old pending statements and
earlier implementation descriptions do not override this table.

Original qualified shipping source: `aa6e298cd89aadd37b27d69e9c8c957f39c3d409`.
The current UInt12 reader refinement has exact source hashes and new evidence in
[UInt12Validation](Qualification/UInt12Validation/README.md).
Predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.
Suite policy: 0.10.0. Earlier development harness qualification did not change the library. Its exact hashes are in
[Qualification/results.json](Qualification/results.json).

| Requirement | Evidence / current disposition |
| --- | --- |
| Pinned source, product inventory, licences (POL-05/07; milestone 2) | Passed provenance verifier: 57 principal paths, 56 original source hashes, generated identity fixture and ICC asset/notice. Product dispositions remain in IMPLEMENTATION.md. |
| Independent library and common contract (POL-01–04) | No shipping package dependency. Fresh URL consumer resolves the exact shipping revision and exercises predictive, progressive, float, XYB and explicit colour policies. Actual contents of all 28 shared documents match across four pinned repositories. |
| Public API and ownership (API-01–13; MEM-01–10) | Implemented public codec/storage surface, checked descriptors, leases and bounded operations; covered by API, descriptor, ownership, sample-access, limit and publication tests. This does not make every descriptor layout a codec capability. |
| Native JPEG coverage (milestones 2/4) | SOF3 unsigned 2–16-bit lossless/point-transform, SOF0/1/2 8/12-bit lossy, scale, metadata, explicit float/XYB/RGBA/YCbCr/greyscale policies implemented. MIGRATION.md defines supported combinations and rejection boundaries. |
| Predecessor fidelity (TEST-04/09) | 71 executed native identity records; 118 public colour-policy comparisons; ordinary and expanded public benchmark cases preserve bytes/samples. Original source pin remains unchanged. |
| Independent JPEG oracles | Retained libjpeg-turbo predictive and DCT bidirectional matrices, and colour interpretation checks. Added licensed libjpeg-turbo source images, six independent 4:4:4 pixel oracles, real embedded ICC preservation and arithmetic rejection tests; nine public decodes match the predecessor. See Qualification/UpstreamCorpus. These finite matrices are not a universal JPEG conformance claim. |
| Direct source/destination storage (MEM; TEST-09) | Padded/guarded scalar and accelerated matrices; four executed stride/endian mutants; current-source Linux encoder 30+30 and decoder 60+60 allocator/control measurements. See RGBInput and StorageMutations. |
| Cross-codec extension (TEST-03; milestone 3) | SwiftJ2K ↔ SwiftJLI: six 12/16-bit odd/non-square cases, different strides, exact bytes/samples, concurrent readers, sealed mutation rejection, processing-callback cancellation/retry, incompatible endian rejection, 12 independent decodes; separate ASan/TSan runs pass. Linux allocator gives one destination per measured hand-off and exactly one extra with deliberate-copy controls. File tracing sees only final compressed outputs. [Harness](../../Examples/CrossCodecIntegration/README.md). |
| Cross-codec coverage limits | Current SwiftJLS main `91092f78b492e332a7ec200e68b76604088e44fb` has contract-only capabilities. Pinned SwiftJ2K rejects HTJ2K. Those pairs cannot be qualified against these revisions. No signed metadata mapping, successful copy-conversion fallback or mid-kernel cross-codec cancellation claim is made by this harness. |
| Full build/test matrix (PLAT-01; TEST-07) | CI 37752829169 retry passes all eight jobs at the shipping revision: Linux Swift 6.2/6.4 on ARM/x86, independent consumer, common hashes, macOS debug/release/ASan/TSan, nine Apple SDK targets. First attempt failed to obtain macOS runners; it was not a code failure. |
| Local/macOS and Linux CLI foundation (CLI; I3) | 107 process/install/manual checks pass on each host. The minimised Linux image needs its real man-db executable instead of the image's message-only stub; CI setup now handles this. Payload verbs remain explicitly deferred under I3. |
| Fuzzing (TEST-05) | The four-entry campaign against aa6e298 was interrupted after about 44 minutes by host idle sleep and the watchdog correctly failed it. It is not a one-hour pass. A fresh current-source campaign must complete with task-scoped sleep prevention. |
| Performance (PERF-01–03) | **Open.** Large RGB and predictive regressions were corrected with attribution and identity checks. The fused UInt12 range check reduces its measured overhead; progressive decode and some small/512² cases still exceed the investigation threshold. No waiver or complete performance pass. |
| Memory under failure/cancellation and workspace (PERF-05; TEST-05/09) | Functional cancellation/failure/join tests and sanitizer evidence exist. New MemoryStress evidence passes 28 Linux scopes/controls and 56 Apple scopes/controls for concurrent operations, admission denial, invalid samples and processing-callback cancellation. Complete pure-workspace attribution and exhaustive allocator failure injection remain open. Requested-heap bins are not pure workspace, RSS or detection of every possible copy shape. |
| Native Apple runtime matrix (PLAT-01–05) | At 0a714f3, native macOS Intel runtime/CLI passes, and the iOS library suite passes 347 tests. The first executed iOS suite exposed use of macOS floating-point snapshots on iOS; the corrected platform guard is supplemented by a live pinned predecessor comparison, whose CI scheme-name failure is corrected and awaits rerun. tvOS/visionOS/watchOS runtime and Watch device resource validation remain unexecuted. SDK compilation is not runtime proof. |
| Build-associated SBOMs (PLAT Swift 6.4 qualification) | Swift Build emits SPDX 3.0.1 and CycloneDX 1.7. Independent schema validation passes CycloneDX but rejects two SPDX package records (`externalUrl`, `software_internalVersion`). Raw generated files and failures are preserved; generation is not falsely reported as successful schema validation. |
| Release preparation (milestone 5) | URL consumption, docs, provenance and CLI evidence refreshed. Complete acceptance/review remains open. Stable tag, merge, predecessor retirement and application cutover are separate actions; none has occurred. |

The repository still needs the open performance, memory and applicable
runtime evidence before an unconditional completion claim. Unavailable external
codec capabilities are explicitly identified rather than replaced by stubs or
runtime oracle fallbacks. The supplied common contracts remain byte-identical.
