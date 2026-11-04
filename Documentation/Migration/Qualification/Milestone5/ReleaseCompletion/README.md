# Milestone 5 consumer and stable-release completion — 4 November 2026

**In progress. Physical-device qualification, actual DICOMKit integration and stable publication are now assigned.** The owner expanded the earlier release-preparation scope on 4 November. The [3 November completion receipt](../completion.json) remains evidence for its explicitly frozen, simulator-only task scope; it does not close these newly assigned requirements.

The [source-preservation checks](source-preservation.json) retain the qualified library, original completion receipt and all seven common contracts unchanged.

## Source and release identity

- SwiftJLI starting revision: `87bc4e9f99ddaf8c592ec9dfe09120c043a768ff`, with library implementation matching qualified shipping source `f548e5048e5c71204c2a2ec4036bf66c4f040285` and suite policy `0.10.0`.
- Earlier [PR #26](https://github.com/raster-labs/SwiftJLI/pull/26) targets `codex/milestone-5-baseline-8ae2762` at `8ae2762710d6279cd92222f5bb5ca95f042f694e`. Its merge would update that branch, not `main`. No concurrent performance branch is implicitly included by this task.
- Current DICOMKit baseline: `5756e6408a95649b463d4a6408f2957fe1b4c212`, freshly retrieved from `raster-labs/DICOMKit` on 4 November. Its manifest, dependency lock, JPEG adapter, image-codec protocols and allocation contract are byte-identical to the earlier inspected `ff9d26fc6336340f7a5046419d9ac164e341eb0d`.
- Intended stable version: `1.1.0`. The starting candidate identifies itself as `1.1.0-dev.2`. This branch prepares `1.1.0` consistently in VERSION, CLI source, manual and current guides. No stable tag or release is published. Metadata promotion creates a new revision and requires matching CLI, manual, installer, consumer and SBOM evidence.

## Required work

| Requirement | Current disposition |
| --- | --- |
| Physical devices | Current inventory exposes simulators and the host Mac, with no physical iPhone, iPad or Watch. Real hardware, signing and synthetic test execution remain necessary. SDK compilation and simulator results do not satisfy this gate. |
| DICOMKit integration | Existing managed paths require admitted caller workspace, scalar failure outcomes and a synchronous worker. The frozen SwiftJLI public API exposes owning async operations but not this managed interface. Consumer baseline qualification and an explicit adoption design precede changes. |
| Consumer scope | Suite policy Decision D3 requires a coordinated four-codec cutover and Apple minima of 26.0. The owner has been asked whether this assignment means that full migration or an explicitly staged SwiftJLI integration retaining the existing managed routes. No scope exception or weakened allocation contract is inferred. |
| Stable publication | Authorised after the required gates pass. Select the exact qualified revision, reconcile release metadata, validate clean versioned consumption and publish precise capability/release notes. Publication is pending physical and consumer acceptance. |

## Completed preparation

The [physical Watch verifier checks](watch-device-verifier-checks.json) pass eleven focused parser, provenance and rejection tests, including rejection of the retained genuine simulator capture. The [device inventory](device-inventory.json) records no connected physical device. These are preparation results, not physical qualification.

The [prepared 1.1.0 CLI metadata](release-metadata/README.md) passes the explicit Swift Build Release build and 250 process checks, including staged installation and matching manual validation. The library implementation remains frozen; final stable publication and versioned consumer/SBOM evidence are pending.

The [unchanged DICOMKit baseline](dicomkit-baseline/README.md) passes 54 test declarations in eight selected JPEG, allocation and managed-ownership suites, exit 0. This is predecessor-backed Debug coverage, not successor integration or full consumer qualification.

## Execution and evidence rules

The existing simulator verifier and its qualified records remain unchanged. Physical Watch evidence must use six real `physical-watch` records, six passing Release tests without failures or skips, matching hardware/source/toolchain identity and preserved original result bundles. The harness covers bounded synthetic cases; repeated memory and cancellation recovery on the device still needs explicit review. Representative iPhone/iPad execution remains an additional requirement.

DICOMKit integration must preserve source/frame identity, DICOM process restrictions, precision, signed interpretation, colour metadata, cancellation and owner lifetime. A new asynchronous compatibility API may deliberately copy into `Data` only with finite limits and truthful accounting. It cannot be substituted for the existing managed allocation route. No semaphore bridge or escaping synchronous pointer borrow is acceptable.

Release checks attach to the final source, not just its ancestry. A metadata-only stable promotion can preserve library evidence through exact source comparisons, but changed CLI/version/manual artefacts and final dependency resolution need their own results. If a required implementation change invalidates the frozen source evidence, the affected correctness, memory, security, platform and performance gates must be rerun before publication.
