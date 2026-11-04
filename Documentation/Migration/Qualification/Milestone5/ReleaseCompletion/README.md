# Milestone 5 release preparation — 4 November 2026

**Library release preparation is complete for the owner's resumed scope. Actual DICOMKit integration and physical-device testing remain pending; stable publication remains gated.** The [current completion record](../LibraryCompletion/README.md) records this disposition and the final audit. The owner initially expanded the task to consumer/device/publication work, then paused it and resumed only the remaining library tasks. The preparation evidence below remains bound to its original revisions and capture times.

The [3 November completion receipt](../completion.json) remains evidence for its earlier frozen, simulator-only scope. Neither that receipt nor this library closure completes the separately pending consumer and hardware requirements.

The [source-preservation checks](source-preservation.json) retain the qualified library, original completion receipt and all seven common contracts unchanged.

## Source and release identity

- SwiftJLI starting revision: `87bc4e9f99ddaf8c592ec9dfe09120c043a768ff`, with library implementation matching qualified shipping source `f548e5048e5c71204c2a2ec4036bf66c4f040285` and suite policy `0.10.0`.
- Earlier [PR #26](https://github.com/raster-labs/SwiftJLI/pull/26) targets `codex/milestone-5-baseline-8ae2762` at `8ae2762710d6279cd92222f5bb5ca95f042f694e`. Its merge would update that branch, not `main`. No concurrent performance branch is implicitly included by this task.
- Current DICOMKit baseline: `5756e6408a95649b463d4a6408f2957fe1b4c212`, freshly retrieved from `raster-labs/DICOMKit` on 4 November. Its manifest, dependency lock, JPEG adapter, image-codec protocols and allocation contract are byte-identical to the earlier inspected `ff9d26fc6336340f7a5046419d9ac164e341eb0d`.
- Intended stable version: `1.1.0`. The starting candidate identifies itself as `1.1.0-dev.2`. This branch prepares `1.1.0` consistently in VERSION, CLI source, manual and current guides. No stable tag or release is published. Metadata promotion creates a new revision and requires matching CLI, manual, installer, consumer and SBOM evidence.

## Separate pending work

| Requirement | Current disposition |
| --- | --- |
| Physical devices | Pending at the owner's request. The [recorded confirmation](hardware-availability.json) states no physical devices are available. Real hardware, signing and synthetic test execution remain necessary; SDK compilation and simulator results do not satisfy this gate. |
| DICOMKit integration | Pending at the owner's request. Partial managed/ordinary successor integration exists separately in [draft PR #28](https://github.com/raster-labs/SwiftJLI/pull/28) and isolated consumer worktrees. It has not completed combined acceptance and is excluded from this frozen candidate. |
| Consumer scope | Suite policy Decision D3 requires a coordinated four-codec cutover and Apple minima of 26.0. That migration remains separate and pending; no exception or weakened allocation contract is inferred. |
| Stable publication | Authorised after the required gates pass. Select the exact qualified revision, reconcile release metadata, validate clean versioned consumption and publish precise capability/release notes. Publication is pending physical and consumer acceptance. |

The [four-codec source inventory](ConsumerPrerequisites.md) records available managed JPEG-LS support, the remaining JPEG gap and concrete JPEG XL/JPEG 2000 adapter constraints. It does not claim successor integration.

## Completed preparation

The [physical Watch verifier checks](watch-device-verifier-checks.json) pass eleven focused parser, provenance and rejection tests, including rejection of the retained genuine simulator capture. The [device inventory](device-inventory.json) records no connected physical device. These are preparation results, not physical qualification.

The [prepared 1.1.0 CLI metadata](release-metadata/README.md) passes the explicit Swift Build Release build and 250 process checks, including staged installation and matching manual validation. The library implementation remains frozen.

The [fresh URL consumer and product SBOM checks](prepared-consumer-sbom/README.md) pass for prepared revision `7739dba554cabebcc25e3593af3feb6ba27f8489`. Clean and incremental Debug/Release consumer builds and both executions pass. Both library and CLI derived SBOMs pass official schemas and SPDX SHACL validation; original producer defects and failed raw SPDX validation remain preserved. This verifies exact-revision consumption, not a stable tag, DICOMKit integration or physical execution.

The [separate deterministic replay](prepared-consumer-sbom-replay/README.md) reproduces all 12 compared library/CLI derivative outputs byte-for-byte. It preserves the original committed archive and adds no runtime or device claim.

The [archive review](archive-review.json) verifies evidence hashes and documentation links. Two generated SHACL results and two raw Watch compiler/test logs retain their original whitespace; the unfiltered check and the otherwise-clean filtered check are recorded without rewriting captured output.

The [current repository check](repository-state.json) confirms private vulnerability reporting is enabled. It also confirms no tags or releases are published at the recorded time.

The [full hosted CI matrix](ci-41781795793/README.md) passes all 13 jobs at prepared revision `7739dba554cabebcc25e3593af3feb6ba27f8489`, including native macOS Debug/Release/AddressSanitizer/ThreadSanitizer, Linux/compiler combinations, Apple SDK/simulator jobs and independent consumption. The Watch job passes its library suite, six-case Release harness and strict simulator verifier. These are hosted software results; no physical-device or DICOMKit successor execution is implied.

The [unchanged DICOMKit baseline](dicomkit-baseline/README.md) passes 54 test declarations in eight selected JPEG, allocation and managed-ownership suites, exit 0. This is predecessor-backed Debug coverage, not successor integration or full consumer qualification.

## Execution and evidence rules

The existing simulator verifier and its qualified records remain unchanged. Physical Watch evidence must use six real `physical-watch` records, six passing Release tests without failures or skips, matching hardware/source/toolchain identity and preserved original result bundles. The harness covers bounded synthetic cases; repeated memory and cancellation recovery on the device still needs explicit review. Representative iPhone/iPad execution remains an additional requirement.

DICOMKit integration must preserve source/frame identity, DICOM process restrictions, precision, signed interpretation, colour metadata, cancellation and owner lifetime. A new asynchronous compatibility API may deliberately copy into `Data` only with finite limits and truthful accounting. It cannot be substituted for the existing managed allocation route. No semaphore bridge or escaping synchronous pointer borrow is acceptable.

Release checks attach to the final source, not just its ancestry. A metadata-only stable promotion can preserve library evidence through exact source comparisons, but changed CLI/version/manual artefacts and final dependency resolution need their own results. If a required implementation change invalidates the frozen source evidence, the affected correctness, memory, security, platform and performance gates must be rerun before publication.
