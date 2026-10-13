# Migration acceptance ledger — 13 October 2026

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

The three maintenance gaps merged through [PR #21](https://github.com/raster-labs/SwiftJLI/pull/21)
on 13 October 2026 as `e1ae85dff9da3fb150ef5fc6197be9756d8d4676`.
[Post-merge CI 38355780498](https://github.com/raster-labs/SwiftJLI/actions/runs/38355780498)
passed all 13 jobs. The complete tree matches final PR head `abc0e87e`.
Its codec source is `ba39fda`; `c0c697f` repairs only regression
compilation and the live predecessor comparison. [JPEGDecodeParity.md](JPEGDecodeParity.md)
records the same independent fixtures, scoped source pins, verification and costs.
Executable non-Watch qualification is now complete in
[NonWatchCompletion](Qualification/NonWatchCompletion/README.md). Full
stable-release acceptance remains open for physical Watch testing and
administrator activation of private reporting (deferred by the owner on 13 October 2026); finite regressions do not waive
those requirements.

The refreshed record covers current shipping source e7e54f7. Historical broad
fuzz, memory and oracle qualification retains source `0a714f3` and other
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
| Independent library and common contract (POL-01–04) | No shipping package dependency. Fresh remote-URL consumer resolves e7e54f7 and passes predictive, progressive, float, XYB, RGBA, YCbCr and greyscale policies. Actual contents of all 28 shared documents match across four refreshed immutable repository pins. |
| Public API and ownership (API-01–13; MEM-01–10) | Implemented public codec/storage surface, checked descriptors, leases and bounded operations; covered by API, descriptor, ownership, sample-access, limit and publication tests. This does not make every descriptor layout a codec capability. |
| Native JPEG coverage (milestones 2/4) | SOF3 unsigned 2–16-bit lossless/point-transform, SOF0/1/2 8/12-bit lossy, scale, metadata, explicit float/XYB/RGBA/YCbCr/greyscale policies implemented. MIGRATION.md defines supported combinations and rejection boundaries. |
| Predecessor fidelity (TEST-04/09) | The original 71-record fixture remains intact. PR #21 preserves all encoded identities and 64 decoded identities; seven corrected decoded records match the fixed predecessor v0.5.2. The live comparison runs both pins to cover all records on the same runtime. Historical evidence also includes 71 executed native identity records; 118 public colour-policy comparisons; ordinary and expanded public benchmark cases preserve bytes/samples. Original source pin remains unchanged. |
| Independent JPEG oracles | Current-source requalification passes 210 predictive cases in both directions exactly; 48 DCT profiles in both directions have maximum difference 2 (established limits 2/4 for 8/12 bits). The new raw-RGB matrix passes 16 scalar/automatic and allocating/padded-destination combinations with maximum difference 1. The original 15 chroma fixtures and strict padding/budget regressions pass. Prior licensed upstream-corpus and ICC evidence remains separately recorded. |
| Direct source/destination storage (MEM; TEST-09) | Current-source Linux decoder 60+60 and encoder 30+30 allocator/control measurements pass. New raw-RGB and existing chroma tests check caller allocation identity, zero handoff copies and prefix/row padding. Necessary component planes are accounted algorithm workspace. Earlier stride/endian mutation evidence remains historical; the expanded suite heap verifier independently rejects an injected extra-allocation record. |
| Cross-codec extension (TEST-02/03; milestone 3) | Refreshed current peer pins now implement all four codecs. The development-only [SuitePairIntegration](../../Examples/SuitePairIntegration/README.md) passes all twelve directions on six 12/16-bit odd/non-square cases: 72 exact byte/sample handoffs and 72 independent oracle decodes. Different strides, shared owners, concurrent readers, sealing, callback cancellation/retry and incompatible dimensions are checked. ASan/TSan pass separately. Linux measures 72 single-destination cases plus 72 deliberate-copy controls; tracing sees only 72 final compressed writes and the harness process. |
| Cross-codec coverage limits | Pins: SwiftJ2K `be4e7a3`, SwiftJLS `f481f60`, SwiftJXL `2534240`; full revisions are in the harness manifest. The older contract-only SwiftJLS exception no longer applies. HTJ2K remains unavailable at the pinned SwiftJ2K revision. The finite common profile is unsigned greyscale lossless 12/16-bit; no signed metadata mapping, successful conversion fallback, multi-frame or coefficient/reconstruction transcoding is inferred. SwiftJXL allocation reports remain unknown; independent telemetry supplies the tested handoff evidence. |
| Full build/test matrix (PLAT-01; TEST-07) | CI [38241825202](https://github.com/raster-labs/SwiftJLI/actions/runs/38241825202) passes all 13 jobs for e7e54f7. Its synthetic merge checkout 5079cb7 has byte-identical source, tests, package, scripts and workflow. Linux Swift 6.2/6.4 ARM/x86 passes 349 tests in debug/release; native macOS ARM/Intel and all four simulators pass 354 tests. Mac ARM ASan/TSan, both live iOS predecessor comparisons, SDK targets and the tools-6.2 consumer pass. Subsequent additions are separately qualified development harnesses and documentation, not shipping-source changes. |
| Local/macOS and Linux CLI foundation (CLI; I3) | The candidate CI passes 107 process/install/manual checks on Linux 6.4 ARM/x86 and native macOS Intel. Earlier local ARM CLI evidence remains recorded; CLI source is unchanged. Payload verbs remain explicitly deferred under I3. |
| Fuzzing (TEST-05) | Current-source inspect, inspectJPEG, allocating-decode and destination-decode campaigns each complete a full hour with zero unresolved crash/hang/bounds finding. Source and executed binary hashes were rechecked. See [NonWatchCompletion/fuzz](Qualification/NonWatchCompletion/fuzz/campaign.json). These deterministic release campaigns are distinct from sanitizer tests and are not coverage-guided security certification. Earlier failed/successful campaigns remain historical. |
| Performance (PERF-01–03) | **Qualified with explicit safety/correctness trade-offs for this matrix.** The AC follow-up preserves all 140 output comparisons with stable power/settings and nominal thermals. Forty-three of 140 operation cases cross 5% in both repeats: 30 tiny cases add 1.04–22.54 μs, nine larger UInt12 encoder cases add 0.18–5.87 ms, and four 512² RGB/progressive encoder cases add 0.17–0.31 ms. The earlier battery matrix and its 40 repeated crossings remain a separate record. Source review and repeated native/context/shared/public diagnostics localise the required validation, cancellation and borrowed-read costs. Every flagged case has its measured cost, reason, spread and updated successor baseline in [AC disposition](Qualification/NonWatchCompletion/performance-ac/disposition.json); no unexplained confirmed case remains in this finite matrix. This is not a no-regression or universal-speed claim. |
| Memory under failure/cancellation and workspace (PERF-05; TEST-05/09) | Current-source Linux stress 28+28 and Apple stress 56+56 scopes/controls pass. Isolated-memory requalification retains 120 fresh-process comparisons and 54 attribution controls, all outputs exact. Required asynchronous execution and bounded compressed-input materialisation explain above-threshold RSS costs; all residual median differences are below 5% in this matrix. Explicit costs, spread and the successor baseline are in NonWatchCompletion. This does not measure pure workspace or certify every allocation failure; public peakWorkspaceBytes remains unknown. |
| Native Apple runtime matrix (PLAT-01–05; TEST-06) | Native ARM/Intel and iOS/tvOS/visionOS/watchOS simulators pass at the candidate shipping source. Each simulator passes 354 tests; iOS additionally passes both pinned predecessor comparisons. **Physical Watch resource validation remains unexecuted**; it is still a separate release qualification limit. |
| Build-associated SBOMs (PLAT Swift 6.4 qualification) | Refreshed build-associated CycloneDX 1.7 passes independent schema validation. Raw SPDX 3.0.1 still fails two producer records containing externalUrl/software_internalVersion. Versioned schemas, validator version, raw generated files and failures are retained in NonWatchCompletion/sbom. The documented toolchain discrepancy is not silently corrected or called a schema pass. |
| Release preparation (milestone 5) | URL consumer, documentation, provenance, SBOM generation and candidate qualification refreshed; supported-version policy recorded. The owner has deferred private-reporting activation to a later administrator task; it remains a stable-release prerequisite. Physical Watch remains unexecuted. PR #21 is merged. Milestone 5 is deferred by the owner to a later task; stable tag publication, predecessor retirement and application cutover remain separate tasks. |

All recorded executable non-Watch qualification is complete. The owner has now
assigned Milestone 4 and deferred Milestone 5. The [Watch harness and current
assessment](Qualification/Milestone4/README.md) prepare the remaining device work.
No physical Watch is connected to the current host, and device resource testing
remains unexecuted. An administrator must establish the private reporting channel in the owner-deferred follow-up. These limits prevent unconditional
stable-release completion. Unsupported capabilities remain explicit, and the
supplied common contracts remain byte-identical.

## Remaining work and completion criteria

| Work | Required evidence or disposition |
| --- | --- |
| Performance acceptance — completed for measured scope | The controlled final-source comparisons and explicit PERF-03 dispositions are in NonWatchCompletion. All 43 repeated above-threshold AC cases have retained measurements, source-path explanations, diagnostic evidence and updated baselines. The earlier battery record retains its separate 40-case assessment. No guard, precision check or zero-copy requirement was relaxed. This replaces the earlier open 44-case historical result; it does not erase it. |
| Physical Watch resource validation — pending hardware | The [development harness](../../Examples/WatchQualification/README.md) has host validation and Watch SDK compilation only. Execute a device harness on supported physical Watch hardware with the documented default budgets; record model/OS/revision, memory and latency, boundary/admission failures, repeated work, cancellation and deadline behaviour. Adjust defaults conservatively through a shared-contract revision if necessary; simulator evidence is insufficient. |
| Final candidate evidence reconciliation — completed for shipping source | All 13 candidate CI jobs, four full-hour fuzz campaigns, refreshed oracles, 72 four-codec handoffs, allocator/stress controls, isolated memory and controlled performance evidence cover the recorded shipping source. Later changes are separately tested development harnesses, evidence and documentation. Raw SPDX schema failures remain explicitly reported as a toolchain discrepancy. Stable version/tag publication requires a separate release task after outstanding release limits. |
| Security release preparation — owner-deferred activation | Supported-version policy is now recorded in SECURITY.md. GitHub private vulnerability reporting remains disabled; the authenticated account can push but cannot administer repository settings (activation returned HTTP 404). The owner explicitly deferred activation on 13 October 2026. An administrator must activate it or supply an established private reporting contact before stable release; this deferral does not waive that requirement. The prepared advisory URL is not represented as active. |
| Application adoption / predecessor maintenance | Consumer dependency changes, deployment-floor changes, fixture acceptance, rollback and predecessor maintenance announcements are separate work; no application repository was cut over by PR #19. |

`JLIDICOM` and `JLIBench` remain deferred products under I1/I2; their required
fixture obligations are accounted for by provenance. CLI encode/decode/inspect/
validate payload commands remain separate new work under I3. Unsupported codec
profiles and unavailable cross-codec pairs remain capability limits, not completed
features. They must not be converted into an unqualified “all migration done” claim.
