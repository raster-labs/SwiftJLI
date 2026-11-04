# Milestone 5 library completion — 4 November 2026

**Complete for the owner's resumed library release-preparation scope.** The owner instructed: “Resume milestone 5 and complete all remaining library tasks. Keep DICOMKit integration and physical-device testing pending for now.” This record closes the frozen library candidate's remaining evidence and documentation work. It does not complete the separately pending integration, hardware or stable-publication requirements.

The reviewable change is [PR #27](https://github.com/raster-labs/SwiftJLI/pull/27), based on immutable branch `codex/milestone-5-release-baseline-87bc4e9` at `87bc4e9f99ddaf8c592ec9dfe09120c043a768ff`. The base is not `main`, and no merge is performed. Prepared shipping revision is `7739dba554cabebcc25e3593af3feb6ba27f8489`; library sources and `Package.swift` remain byte-identical to `f548e5048e5c71204c2a2ec4036bf66c4f040285`. Suite policy is 0.10.0, manifest minimum Swift 6.2, primary qualified toolchain Swift 6.4 and Apple deployment minimum 26.0.

## Evidence review

| Library requirement | Accepted evidence and final review |
| --- | --- |
| Source identity and independence | [Source review](source-review.json) checks all 46 shipping Swift files, seven common documents and 17 original acceptance references. No executable source, test, manifest, workflow or helper changed in this closure. The package retains no runtime dependency on another suite codec. |
| Correctness, sanitizers and samples | [Retained library validation](../final-validation/README.md) passes 389 tests in 60 suites for each of Debug, Release, ASan and TSan, without failures/skips. [JPEG oracles](../final-rgb/README.md) and [suite interoperability](../final-suite/README.md) retain independent tools, fixture provenance, exact-sample checks and explicit lossy thresholds. |
| Allocation, copies and owner lifetime | [Decoder](../final-allocation/results.json), [encoder](../final-encode/results.json), [failure/cancellation](../final-stress/results.json) and [Apple retained-frame](../final-apple-memory/README.md) records retain measured allocation/copy controls and recovery checks at the unchanged source. No device ceiling or universal no-copy claim is inferred. |
| Fuzzing and performance | [Four complete hour-long campaigns](../final-fuzz/README.md) and the [matched performance comparison](../performance/controlled-summary.md) remain applicable to the frozen source. The comparison records 24 exact pre-timing byte checks and no above-5% median-latency or maximum peak-RSS increase in either accepted round. Earlier loaded/failed attempts remain separate. |
| Version, CLI and manual | Prepared version 1.1.0 is consistent across VERSION, CLI/help, manual and guides. The [prepared metadata qualification](../ReleaseCompletion/release-metadata/README.md) passes the Release build and 250 process checks, including staged installation and manual validation. |
| Clean remote consumption | The [prepared-revision consumer](../ReleaseCompletion/prepared-consumer-sbom/consumer/report.json) resolves only SwiftJLI at the exact GitHub revision, passes clean/incremental Debug/Release builds and both executions, without local sibling dependencies. This proves revision consumption, not a published version tag. |
| Product SBOMs and notices | Both derived library/CLI products pass official JSON Schemas and SPDX SHACL, with identities, source licences and ICC notices bound to captured inputs. [Raw producer defects](../ReleaseCompletion/prepared-consumer-sbom/README.md) remain disclosed. The [separate replay](../ReleaseCompletion/prepared-consumer-sbom-replay/README.md) reproduces all 12 compared outputs byte-for-byte. [Independent review](sbom-audit/receipt.json) verifies 170 original archive entries, nine replay entries, eight schema copies, 44 inputs and 47 Git-object source bindings. |
| Hosted platforms and security channel | [Live read-only audit](hosted-audit/receipt.json) confirms all 13 jobs of [run 41781795793](https://github.com/raster-labs/SwiftJLI/actions/runs/41781795793) passed at `7739dba`, private reporting is enabled, and no stable tags/releases exist. All nine SDK target builds selected the complete library; the retained Watch Release compiler log lists all 45 library sources. Watch runtime results are explicitly simulator evidence. |

Exact commands, exits and hashes are in the linked receipts. The final review performs no new codec build, test, fuzz campaign, benchmark or device execution. The later documentation/evidence commits preserve the tested source; they are not represented as separate full-matrix passes. The 13 jobs are project acceptance gates, not verified GitHub-enforced branch-protection checks.

## Change and remaining work

This closure updates current scope/status, archives the already executed SBOM replay and retains independent source/hosted/SBOM audits. Public API, unsafe operations, sample/fidelity policies, resource defaults, copy behaviour and measured performance/memory remain unchanged. Historical evidence and raw tool failures are preserved.

- Actual four-codec DICOMKit integration remains pending. Its SwiftJLI API extension is in [draft PR #28](https://github.com/raster-labs/SwiftJLI/pull/28); consumer changes remain in isolated worktrees without combined acceptance. Those new APIs, partial tests and interrupted campaigns are excluded from this acceptance.
- Physical Watch and representative iPhone/iPad tests remain pending. Simulator and SDK evidence does not replace them.
- Stable-tag/version-range consumption, stable publication and predecessor retirement remain pending. Prepared 1.1.0 metadata is not a published release; required device and consumer acceptance still gates publication.

[completion.json](completion.json) records this scope, evidence hashes and pending requirements. [artifact-manifest.json](artifact-manifest.json) binds the final local record.
