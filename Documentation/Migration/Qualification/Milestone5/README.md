# Milestone 5 release preparation — 3 November 2026

**In progress; stable-release acceptance remains open.** The owner assigned
Milestone 5 on 3 November 2026. This record supersedes earlier statements that
the milestone is deferred, without rewriting historical qualification results.

The starting candidate is `8ae2762710d6279cd92222f5bb5ca95f042f694e`, the head of
[PR #25](https://github.com/raster-labs/SwiftJLI/pull/25). Its 46 shipping Swift
source files match the hashes recorded at `5351088` in the
[3 November checkpoint](../DjpegPerformanceRound3_20261103/README.md).
The isolated branch is `codex/milestone-5-release-preparation`; unrelated edits
in the original checkout are excluded. Suite policy stays at **0.10.0**, the
manifest floor at Swift **6.2**, the primary toolchain at Swift **6.4**, and
Apple deployment minima at **26.0**.

Original migration provenance remains JLISwift
`0a4ded0b0b2e8e38127f4f302b286e74ee352474`; subsequent maintenance pins and
fixture origins remain separate. No release tag, predecessor retirement or
application cutover is performed by this milestone.

## Acceptance work

| Requirement | Current disposition |
| --- | --- |
| Candidate/source identity | All 46 shipping sources match the November evidence; seven common-document hashes pass. |
| Provenance and fixtures | Verifier passes: 57 principal paths, 56 migrated source hashes, one generated fixture, one embedded third-party profile/notice and one external regression manifest. |
| Platform/toolchain CI | Candidate run [41586828694](https://github.com/raster-labs/SwiftJLI/actions/runs/41586828694) passes 11 of 13 jobs. macOS ARM and Intel release tests terminate with signal 11 on Apple Swift 6.3.3 / Xcode 26.6. Debug tests pass; later sanitiser/CLI steps in those jobs are skipped. Investigation remains open. |
| Consumer/build/SBOM | Fresh URL-based consumer and build-associated SBOM qualification underway at the immutable candidate. |
| JPEG fidelity | Separate profile-specific reconciliation underway: subsampled 8-bit regression limit is 3; the November benchmark intentionally retains its stricter limit 2 and timing exclusions. No threshold is changed. |
| Fuzzing | Four supervised full-hour campaigns underway against current source; a running campaign is not a pass. |
| Copy/lifetime/memory | Fresh ordinary-build decoder allocation controls and failure/cancellation stress underway. Historical memory/performance records keep their own pins. |
| DICOMKit readiness | [Current consumer audit and adoption plan](DICOMKitReadiness.md); actual DICOMKit cutover is a separate task. |
| Physical devices | No physical Watch is available, confirmed by the owner on 3 November. Representative iPhone/iPad device evidence also needs reconciliation under PLATFORMS; simulator and SDK runs do not establish it. |
| Private security reporting | Read-only GitHub check on 3 November returns disabled. Current CLI account has push access but no administrator permission. The owner states an administrator can enable reporting; activation is not yet verified. |

## Release boundary

Completion requires reviewed evidence for the required gates. Hardware and
administrator prerequisites are not converted into passes by documentation.
Stable tagging remains a separate explicit release task after acceptance.

The current DICOMKit source audit finds predecessor-only caller-workspace and
managed-allocation obligations. A basic SwiftJLI consumer does not prove those
obligations; the adoption report records the separate integration work.
