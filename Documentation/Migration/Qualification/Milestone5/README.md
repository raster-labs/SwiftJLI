# Milestone 5 release preparation — 3 November 2026

**The original frozen-candidate, simulator-only scope is complete. The [4 November extension](ReleaseCompletion/README.md) assigns physical-device qualification, DICOMKit integration and stable publication; that expanded scope is in progress.** The owner assigned
Milestone 5 on 3 November 2026. This record supersedes earlier statements that
the milestone is deferred, without rewriting historical qualification results.

The current shipping candidate is **`f548e5048e5c71204c2a2ec4036bf66c4f040285`**.
It corrects the native macOS release crash by retaining task-local host
cancellation callbacks in an immutable `Sendable` owner; a nested throwing-scope
regression verifies restoration. Only `Sources/SwiftJLI/NativeExecution.swift`
changes from the starting candidate, with SHA-256
`695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`.
The other 45 shipping Swift files retain their starting hashes. See the
[source manifest](final-candidate.json) and [crash diagnosis](ci/diagnostic/README.md).

The starting candidate was `8ae2762710d6279cd92222f5bb5ca95f042f694e`, whose 46
shipping Swift files matched the `5351088` [November checkpoint](../DjpegPerformanceRound3_20261103/README.md).
Its pre-fix receipts remain retained separately. PR #26 now uses the pinned
base branch `codex/milestone-5-baseline-8ae2762` at that exact starting revision.
The concurrent performance branch advanced to `bbb0b1a` while qualification
ran; those new codec changes are **excluded** from this candidate and its
results. The owner [confirmed this frozen scope](ci/watch-qualification/base-owner-confirmation.json).
[Base-drift diagnosis](ci/watch-qualification/base-drift.json) and
[resolution](ci/watch-qualification/base-resolution.json) retain the chronology.
The isolated branch is
`codex/milestone-5-release-preparation`; unrelated edits in the original checkout
are excluded. Suite policy stays at **0.10.0**, the manifest floor at Swift
**6.2**, the primary toolchain at Swift **6.4**, and Apple minima at **26.0**.
The seven common documents remain unchanged. Original migration provenance
remains JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`; subsequent
maintenance pins and fixture origins remain separate.

## Accepted release-preparation evidence — 3 November 2026

The completed records below identify the f548 shipping source and each run's
exact configuration. The [completion receipt](completion.json) records task acceptance within the agreed scope; physical-device and downstream release work remain separate.

| Requirement | Current disposition |
| --- | --- |
| Local build/library validation | [Swift 6.4.2 / explicit Swift Build](final-validation/README.md): clean/incremental debug and release builds pass; debug, release, full ASan and full TSan each execute 389 test declarations in 60 suites, with zero failures/skips. All 22 subprocess commands pass. These are four configurations of the same suite. |
| CLI | [250 release process checks](final-cli/report.json) pass against the final local release binary. Earlier ASan CLI receipts retain their original source pins. |
| Platform/toolchain CI | [Run 41601103725](https://github.com/raster-labs/SwiftJLI/actions/runs/41601103725) passes all 13 jobs at test-only candidate `a44e671`, whose shipping sources match f548. [Retained evidence](ci/test-isolation/README.md) includes both native macOS release suites, ASan/TSan, Linux/toolchain coverage, Apple SDK builds, four simulator suites and iOS predecessor comparisons. The original release crash and visionOS deadline-race failures remain separately retained. The dedicated Watch Release harness passes six tests and records; its initial post-check failed on a query-generated SQLite index. The [corrected verifier revalidates that genuine artefact](ci/watch-qualification/verifier-cache-fix/README.md); fresh [Intel Watch run 41622083807](ci/watch-qualification/intel-fallback/run-41622083807/README.md) at `8c1b965` now passes 389 library tests, six Release cases and the strict verifier on watchOS 26.5. This targeted dispatch executes Watch only; seven other job definitions are intentionally skipped. Earlier [capacity outcomes](ci/watch-qualification/run-41608951795/README.md) and the [owner-requested ARM retry](ci/watch-qualification/watch-only-retry-20261103/README.md) remain separately retained and unexecuted. |
| Fresh URL consumer | [Final consumer](final-consumer-sbom/README.md) resolves exactly f548 from GitHub, with no sibling/local-path dependency. Clean/incremental debug and release Swift Build and both executions pass. The separately repaired [local-path consumer](local-consumer/report.json) retains its own earlier run. |
| Build-associated SBOMs | [Separately labelled library and CLI derivatives](final-consumer-sbom/derived/README.md) pass both official JSON Schemas, SPDX SHACL and independent identity/licence checks. Exact transformations and deterministic replay are retained; raw SwiftPM failures remain unchanged. Observed native linkage supplements the package graph without claiming a complete Apple SDK/runtime inventory. [Upstream schema notices](schema-licences/README.md) preserve their separate terms. |
| JPEG fidelity | [Final independent oracles](final-rgb/README.md): 8 subsampled decodes / 16 comparisons pass bound 3; 16 raw-RGB cases pass unchanged bounds 2/4; 210 predictive cases per direction and 48 DCT profiles in both directions pass. Allocating/padded storage outputs and recorded baseline outputs agree. |
| Suite handoff | [72 handoffs, 72 deliberate-copy controls and 72 independent output decodes](final-suite/README.md) pass across all twelve ordered codec pairs, with exact logical samples and identical ordinary/control compressed outputs. Peer revisions and Linux toolchain/image pins are retained. |
| Copy/lifetime/memory | Ordinary Linux [decoder telemetry](final-allocation/results.json) passes 60 measurements + 60 controls; [encoder telemetry](final-encode/results.json) passes 30 + 30; [failure/cancellation stress](final-stress/results.json) passes 28 scopes + 28 controls. Ordinary Apple release [lifetime checks](final-apple-memory/README.md) pass 56 scopes + 56 retained-frame controls. These are finite tested shapes, not universal copy/leak proofs or device memory ceilings. |
| Provenance and fixtures | The retained verifier passes 57 principal paths, 56 migrated source hashes, one generated fixture, one embedded third-party profile/notice and one external regression manifest. The callback-owner change is in locally authored source; predecessor provenance is unchanged. |
| Fuzzing | [All four corrected-candidate campaigns](final-fuzz/README.md) pass at least 3,600 seconds per entry, with zero exit statuses and unchanged source/executable hashes. No crash, watchdog or unresolved bounds finding was reported. These deterministic ordinary-release campaigns are separate from sanitizers and are not security certification. Interrupted pre-fix records remain partial evidence. |
| Performance | [Matched callback-owner comparison](performance/controlled-summary.md) passes the finite PERF-03 screen: maximum median-latency increase 1.334%, maximum observed peak-RSS increase 3.003%, both below 5% in each round. All 24 pre-timing output comparisons are exact. Desktop activity, endpoint-only environment snapshots and noisy latency tails are explicit; this is not an exclusive-host or universal speed claim. |
| DICOMKit readiness | [Current consumer audit and adoption plan](DICOMKitReadiness.md); managed-workspace/execution obligations remain separate, and actual DICOMKit integration is unexecuted. |
| Physical devices | On 3 November the owner confirmed no Watch or iPhone/iPad was available and selected simulators for the original task scope. Physical-device testing remains unexecuted; simulator and SDK runs do not establish device qualification. |
| Private security reporting | Verified enabled on 3 November: [authenticated confirmation](security-activation-confirmed.json) and [independent public confirmation](security-activation-public-verification.json) both return `enabled: true` for `raster-labs/SwiftJLI`, repository ID `1373980250`. The current CLI account still lacks admin access; no settings were changed by the agent. |

## Original completion boundary — 3 November 2026

The original Milestone 5 release preparation completed its agreed frozen-candidate
and simulator scope on 3 November. Verified administrator activation closed that
scope's final prerequisite. Physical qualification, stable tagging and application
cutover were outside that original assignment; the 4 November extension now
assigns them. Predecessor retirement remains separate. Required device evidence
and release acceptance remain open.

At the earlier `8d0f8b4` handoff, the [comparison](final-handoff.json) confirmed
shipping sources matched f548, tests/examples matched the all-13-passing a44
candidate, and executable sources, tests, examples, qualification scripts and
workflow matched `07cc31e`. That documentation-only commit used `[skip ci]`
and did not establish a fresh hosted-verifier pass.

The owner then requested another Watch verification attempt. After the ARM
capacity failure, `8c1b9655319771d1fcaaa7f03c2d165ec3e7a333` added a manual
Watch-only Intel dispatch. The [workflow audit](ci/watch-qualification/intel-fallback/workflow-audit.json)
confirms the ordinary thirteen-job PR/push matrix and all test/verifier steps
remain unchanged. The successful hosted run retains the actual Intel host,
Xcode 26.6 / Swift 6.3.3 and watchOS 26.5 simulator evidence.
[Independent acceptance review](ci/watch-qualification/intel-fallback/run-41622083807/INDEPENDENT_REVIEW.md)
verifies the counts, source identities, complete archive and original-result
preservation without rerunning tests. The
[updated handoff comparison](watch-retry-handoff.json) binds the current shipping
source, tests, helpers and workflow to their tested revisions. The final
documentation/evidence-only commit uses `[skip ci]`; it does not claim another
full-matrix pass.

The final source/evidence [audit](final-audit/README.md) confirms the frozen
base, shipping-source identity and four full-hour campaign receipts. Earlier
[post-Watch](security-watch-retry-final-check.json), [handoff](security-final-check.json)
and [follow-up](security-follow-up.json) checks retain their disabled-state
observations. After the administrator acted, the [recheck](security-activation-recheck.json),
[authenticated confirmation](security-activation-confirmed.json) and
[independent public confirmation](security-activation-public-verification.json)
return `enabled: true` for the canonical repository. The transition is recorded
without attributing it to a cache or propagation cause. No settings, permissions
or security reports were changed by the agent. This closed the original 3 November
release-preparation prerequisite; [administrator verification steps](../../../../SECURITY.md#administrator-activation)
remain available for future maintenance.

The owner-selected scope on 3 November was simulator qualification. The expanded
4 November task now includes physical Watch and representative iPhone/iPad
qualification. The seven common contracts and their device requirements remain
unchanged; the earlier simulator results do not establish these new passes.

The current DICOMKit source audit finds predecessor-only caller-workspace and
managed-allocation obligations. A basic SwiftJLI consumer does not prove those
obligations; the adoption report identifies the integration work now assigned.
