# Change log

## Unreleased — codec migration in progress, 2026-10-07

- Reduce decode overhead with bounded entropy searches, specialised greyscale writes, joined chroma workers and bounded RGB row batches; preserve byte identity and cancellation checks.

- Restore bounded parallel predictive/DCT stages with joined workers, cancellation propagation and backend context; remove impossible full-width sample checks and temporary DCT batch copies.

- Add explicit DCT straight-alpha discard, preconverted YCbCr input and RGB-to-greyscale conversion, using caller storage and reporting conversions. Reject unqualified alpha, precision and ICC combinations.

- Adapt the pinned JLISwift native kernels and tests into internal SwiftJLI sources with per-file provenance.
- Connect the public API to SOF3 lossless encoding/inspection/decoding, including padded shared storage, precision checks, ICC/Exif and bounded operation admission.
- Add Linux scalar DSP and ICC profile hashing; retain the Apple comparator conditionally.
- Add public API, layout, malformed-input and precision/predictor tests plus a repeatable independent libjpeg-turbo oracle.
- Restore the predecessor regression/contract/container corpus and benchmark identity matrix; add explicit bounded-error SOF3 point-transform support.
- Fix concurrent decode scratch initialisation exposed by macOS TSan; CI requalification passed at bcd1201.
- Add public sequential/progressive 8/12-bit DCT controls, direct borrowed storage, explicit scalar/Accelerate selection, bounded kernel cancellation and progressive-input validation.
- Add public reduced-scale and raw greyscale Float32 decode, adaptive trellis/jpegli controls, profile validation and full-frame preview workspace admission.
- Add Apple device/simulator/Intel SDK compilation and macOS release CI gates; runtime qualification remains separate.
- Add opt-in normalised Float32 encoding with fused clamping/quantisation, non-finite rejection and explicit conversion reporting.
- Convert Accelerate strides explicitly for SDKs that import vDSP_Stride as Int64.
- Expose borrowed XYB encoding and direct sRGB integer decoding with explicit colour-conversion reports, accurate ICC output and strict profile/option validation.
- Embed the unchanged ICC sRGB2014 profile with its original copyright, licence and verified byte hash.
- Add explicitly normalised fractional Float32 XYB decode with direct output storage and separate range-conversion reporting.
- Add reproducible, supervised mutation-fuzz campaigns for inspection and both decode entry points.
- Add bounded JPEG-specific inspection for compressed sampling/scan structure, recognised XYB and predictive settings; include its own fuzz entry.
- Restore the predecessor's finite nonnegative distance range and saturate quantisation before integer conversion to avoid large-distance traps.
- Retain independent heap allocation controls, a fresh remote consumer and completed one-hour decoder fuzz evidence at their exact source revisions.
- Broader colour-profile coverage, performance/security and full platform qualification remain open; this is not a completed migration or release. See Documentation/Migration/STATUS.md.

## 1.1.0-dev.1 — Swift 6.4 upgrade, 2026-09-19 (unreleased)

- Require Swift tools/compiler 6.4, retaining Swift 6 language mode and OS 26 deployment floors.
- Advance the coordinated common contract to 0.3.0 and the earlier unreleased 1.0.0 version target to 1.1.0.
- Adopt checked native-order span access for UInt16 samples with explicit endian conversion; preserve public API and owning-storage semantics.
- Add the supplied upgrade references, F01–F13 feature register, headless Swift Build validation and exact evidence. No codec capability, stable release or tag is added.

## Unreleased — application migration documentation, 2026-09-18

- Added [MIGRATION.md](MIGRATION.md) for human and coding-agent upgrades from pinned JLISwift APIs, covering dependencies, API/storage changes, JPEG fidelity/precision, optional products, staged adoption and rollback.
- Linked the guide from README, agent instructions, contributing guidance and the implementation plan. Codec implementation and capability status are unchanged.

## Unreleased — Milestone 1 contract implementation, 2026-09-18

- Final Milestone 1 review: prevent image publication when cancellation occurs inside provider sealing/validation; deterministic regressions and full checks pass.
- Added an independent Swift 6.2-minimum package in Swift 6 language mode, checked sample/plane descriptors, resource profiles and explicit errors.
- Implemented owning sample storage, opaque exclusive write leases, atomic seal/abort lifecycle, retained immutable images and checked unsigned 16-bit sample helpers.
- Added common encoder/decoder API shapes with truthful empty capabilities and explicit unsupported-operation errors. No JPEG algorithm, real inspector, CLI or transcoder is implemented.
- Added synthetic descriptor, lifetime, adapter, concurrent access, cancellation, resource and independent-consumer coverage. Exact executed commands and remaining gates are in `Documentation/MILESTONE1.md`.
- Kept predecessor algorithms, `JLIDICOM`, `JLIBench` and their third-party fixture/oracle qualification deferred to the later migration milestones.

## Unreleased — documentation foundation, 2026-09-17

- Defined the standalone SwiftJLI successor and intended first stable version 1.0.0.
- Added the common API, memory, platform, CLI, testing and performance specifications, codec-specific agent instructions, source provenance and MIT licence.
- No source migration, implementation, package manifest, executable test, binary or release tag is included.
- No runtime behaviour, support matrix or performance result is claimed as verified.

## Documentation clarification — contract 0.1.1, 2026-09-17

- Aligned the suite policy, README and agent handoff with the staged implementation plan: contract feasibility first, codec migration second, shared-storage integration third.
- Added explicit Milestone 1 test evidence and labelled the later codec delivery sections to prevent accidental expansion of the first task.
- Mirrored all seven common documents and regenerated their SHA-256 manifest across the four repositories. API/memory behaviour, platform floors, intended library versions and release gates are unchanged.
- Verified documentation consistency and links; no codec code or executable tests were added or run.

## Native transcoding instructions — contract 0.2.0, 2026-09-18

- Added a common native format-pair API/CLI pattern and explicit in-memory ownership, fidelity and testing requirements for SwiftJ2K and SwiftJXL.
- Distinguished sample-exact J2K ↔ HTJ2K conversion from original-JPEG-byte restoration through JPEG XL. Neither operation requires an umbrella or sibling codec dependency.
- Recorded predecessor implementation/test findings in the relevant repositories; kept Milestone 1 scoped to feasibility. No native transcode placeholder is required in SwiftJLS/SwiftJLI.
- Updated all seven shared documents and their SHA-256 manifest. This is documentation only; no source migration, codec execution or performance claim.

The foundation document version is 0.2.0. It is separate from the intended library version.

## OS 27 and CLI foundation — 19 September 2026

Apple platform floors are 26.0; contract 0.5.0 reverses the 0.4.0 raise to 27.0, which no released SDK, toolchain or CI runner can currently validate. Development version 1.1.0-dev.2, common contract 0.5.0. The standalone `swiftjli` provides help/version/capabilities, five diagnostic levels and a matching section 1 manual installed/updated with the binary. Codec commands remain unavailable. Byte-order sample access uses explicit fixed-width integer conversion and does not raise the runtime floor. See [qualification and limitations](Documentation/Engineering/OS27CLI/README.md). Historical evidence and supplied documents remain unchanged.
## Apple floor restored to 26.0 — contract 0.5.0, 20 September 2026

- Revert the 0.4.0 Apple deployment raise: macOS, iOS/iPadOS, tvOS, visionOS and watchOS return to **26.0**. Xcode 27 is a public preview with a 27.2 beta, no generally available SDK or stable CI runner exists for OS 27, and Swift 6.4.0 rejects a 27.0 deployment target outright because its supported range ends at 26.5.x. The raise could not be validated on any supported configuration.
- Return `swift-tools-version` to **6.2**, keeping Swift 6.4 as the qualified primary toolchain. A manifest floor constrains consumer resolution, and every current consumer resolves at 6.2.
- Replace the OS-27-gated `RawSpan.load(fromByteOffset:as:_:)` and `OutputRawSpan.append(_:as:_:)` byte-order overloads with explicit fixed-width integer conversion. This restores the rule contract 0.3.0 already specified and was the sole reason the floor moved. Public API, ownership and fidelity semantics are unchanged.
- Relax `Scripts/validate-swift64.py` from one pinned preview-Xcode build to accepting Swift 6.2 or 6.4, recording the exact toolchain as evidence rather than enforcing it as an admission gate.
- Retain the OS 27 records under `Documentation/Engineering/OS27CLI` as superseded history for their platform claims; their CLI content remains current.
- Verified on Swift 6.2.4 and Swift 6.4.0, debug and release. No codec capability, stable release or tag is added.

## Shared-storage contract refined from measurement — contract 0.6.0, 20 September 2026

- Advance the coordinated common contract to **0.6.0**. Seven memory rules are amended and one testing rule is added, each from something an exploratory spike measured or broke across all four predecessor codecs in both directions.
- **MEM-03** requires a multi-plane layout to state the distance between plane origins rather than infer it from height and `rowBytes`; with padded rows the two defensible readings differ by one row's padding per plane and shear the image instead of failing.
- **MEM-05** records that read-only storage is shared rather than leased and admits concurrent readers, an asymmetry with destinations the contract did not previously state.
- **MEM-06** requires caller-storage entry points to take the owner rather than a pointer, which an `async` codec cannot otherwise satisfy under MEM-08.
- **MEM-07** requires a safe owning constructor to exist and to be the documented default; unsafe adoption becomes the named exception.
- **MEM-10** requires algorithm workspace to be bounded by a stated per-codec figure, and records that removing the hand-off copy does not by itself reduce peak memory.
- **MEM-12** requires a codec whose native sample order differs from the shared layout to convert on the shared path rather than relax MEM-03.
- **MEM-13** records that allocator telemetry is invalid under a sanitizer, and that encode-side proofs compare codestreams byte for byte rather than comparing samples.
- **TEST-09** collects the resulting evidence bar, including mutation testing to demonstrate the checks are load-bearing.
- This codec is the clearest instance of the public type being the obstacle. `JLIImage` holds a packed, immutable `[UInt8]` with a computed row stride, and its initialiser rejects any buffer whose length is not exactly the packed frame size, so a caller holding a padded plane cannot describe an image without first copying it. Workspace is `Int32` planes at twice the final frame.
- Updated all seven shared documents and their SHA-256 manifest. Documentation only: no source migration, codec execution, platform change or release. Every figure cited comes from a developer machine and none has been reproduced in continuous integration.

## Decision D1: codec libraries stay where they are — contract 0.7.0, 20 September 2026

- Advance the coordinated common contract to **0.7.0**, recording decision **D1**: the shipping codec libraries are the existing repositories, and codec sources are not relocated. Nothing is deleted and no source moves.
- This repository's role is settled: it holds this codec's copy of the seven shared documents, the reference implementation of the shared image layer, and its share of the cross-codec conformance harness. POL-03 already stated that the contract is a specification rather than a runtime module, so the Milestone 1 types built here become that reference rather than discarded work.
- Rationale, from measurement: the Milestone 3 spikes showed all four codec interiors contract-capable through single-point changes, and the obstacle to `requireSharedStorage` is the public image type. That layer is additive work of the same size in either repository, so migration buys nothing it does not also buy, while additionally relocating about 219,000 lines of codec source and 184,000 lines of tests with no CI to catch what breaks.
- Rationale, from arithmetic: the contract repositories hold about 1,000 lines of source each, so abandoning migration discards almost nothing built; three in-house consumers already resolve the existing libraries by URL at pinned released versions and none references a contract repository.
- JLISwift keeps its codec, its 11,375 lines of source and its 5,647 lines of tests, and has no external package dependency at all. Its `JLIImage` initialiser, which rejects any buffer that is not the packed frame size, is the clearest single instance of the public type being the obstacle and is where its contract work starts. It is Apache-2.0 while this repository is MIT; see the note under POL-07. DICOMKit consumes it by URL.
- Updated all seven shared documents and their SHA-256 manifest. Documentation only: no source migration, codec execution, platform change or release. Continuous integration remains blocked and has verified none of this.

## Decision D2: codec libraries relocate into the successor repositories — contract 0.8.0, 22 September 2026

- Decision D2 supersedes D1. JLISwift's codec relocates here; the predecessor becomes a maintenance project and is archived once its consumers have moved. Restores the direction of the repository foundation v0.1.0, reaffirmed by the owner as the guidance for this migration.
- Licence changed from MIT to **Apache-2.0** for this repository, its in-house source and its documentation, amending POL-07 and settling the split that 0.7.0 referred to the owner. LICENSE replaced, NOTICE added, SPDX identifiers updated (27 files).
- Recorded as preconditions rather than resolved: continuous integration must execute before any source moves (Actions billing is still locked, verified 22 September 2026), the POL-05 product inventory must be signed off, and the Apple 26.0 deployment floor against current consumer floors is referred to the owner.
- All seven shared documents stay byte-identical; `SUITE_POLICY.md` and the SHA-256 manifest advance together. No platform, precision, ownership, fidelity or testing rule changes. This revision authorises no codec milestone and no release.

## Product dispositions under POL-05 — 22 September 2026

- Inventoried every JLISwift product and recorded it as retained, adapted or deferred in [IMPLEMENTATION.md](IMPLEMENTATION.md), as contract 0.8.0 §3 requires before any subsystem is relocated. Three products become two: `SwiftJLI` and `swiftjli`. `JLIDICOM` is deferred and retired — it contains windowing, which the memory contract excludes from the codec, and DICOMKit declares it without importing it. `JLIBench` is deferred as development tooling, but its regression corpus and identity hashes migrate under TEST-04.
- Measured at predecessor `0a4ded0` with `swift package dump-package`, with an import census across DICOMKit, CompressionFamily, VoxeliaValidation, DICOMAdapter, RasterOneImage, OneImageViewer-iOS and telerad-dicom-viewer. Every deferred product has zero in-house importers.
- Deferred is not deleted: a deferred product stays with the predecessor through its maintenance window. No shared contract document changes, no source moves, and no release or milestone is authorised by this record.


## Contract 0.9.0: deployment floor stays at 26.0, migration sequence recorded — 22 September 2026

- Decision D3 settles the question 0.8.0 referred to the owner: the Apple deployment floor stays at exactly 26.0 (PLAT-01/02 unchanged), and a consumer raises its own floor to 26.0 in the same change that re-points it from JLISwift to this repository. Until then JLISwift remains its supported route. DICOMKit consumes JLISwift from 0.5.0 at macOS 15 / iOS 18 / tvOS 18 / visionOS 2.
- Corrected the continuous-integration record: J2KSwift now has a CI workflow (its pull request 488, merged 22 September 2026), and every successor carries the Milestone 1 contract workflow. All are written and unexecuted; Actions billing is still locked, verified the same day with `steps=0` on every job. No codec source moves before CI executes and passes here.
- Recorded the programme sequence: preconditions, then JLSwift → SwiftJLS as the pilot, then JLISwift, JXLSwift and J2KSwift, then consumers. This repository is second in sequence, after the SwiftJLS pilot.
- Defined what may proceed before CI runs: documentation, inventories, provenance audits, pin selection, the 0.8.0 item 5 reconciliation choice, and dependency extraction inside the predecessor. Adding predecessor codec or codec-test files here is the line that is not crossed.
- README now states the shared contract version it actually carries (it had read 0.7.0 since 0.8.0). All seven shared documents stay byte-identical; `SUITE_POLICY.md` and the SHA-256 manifest advance together. No platform, precision, ownership, fidelity or testing rule changes. This revision authorises no codec milestone and no release.

## Baseline truth repair — 23 September 2026

- Corrected every active statement of the platform and toolchain baseline to the values the manifests actually declare: **Apple 26.0** and a **Swift 6.2 manifest minimum** with Swift 6.4 as the qualified primary toolchain. Contract 0.4.0's raise to OS 27 was reversed by 0.5.0 and confirmed at 26.0 by 0.9.0 (Decision D3), but nine active locations still asserted the reversed baseline. No contract, platform, precision, ownership, fidelity or testing rule changes; this record corrects statements about the baseline, not the baseline.
- **`swiftjli` reported a false baseline to its users.** The JSON capabilities payload emitted `"minimumAppleOS": "27.0"` and `--help` claimed "Requires Swift 6.4 to build; Apple OS baseline 27.0", against a manifest declaring 26.0 and tools 6.2. Both now derive from one `minimumAppleOS` constant beside `version`, so the help text and the payload cannot drift apart again. `Scripts/test-cli.py` asserted the same wrong value and so agreed with the defect instead of catching it; it now asserts 26.0.
- **The independent-consumer example did not build.** `Examples/IndependentConsumer/Package.swift` still required `swift-tools-version: 6.4` and `.macOS("27.0")`, so `swift build` failed with "package is using Swift tools version 6.4.0 but the installed version is 6.2.3" on the repository's own declared minimum toolchain. README.md's claim that the example "compiles and runs this ownership pattern" was therefore false. Corrected to 6.2 / 26.0; it now builds and runs.
- `ManPages/swiftjli.1` stated "Build with Swift 6.4 in Swift 6 language mode. Apple OS minimum is 27.0" in the manual the installer ships to users. Corrected, and the `.TH` revision date advanced.
- `AGENTS.md` contradicted itself: its "Start here" section recorded the 26.0 floor while "Current platform and CLI direction" told every agent the owner had approved OS 27.0 minima "in contract 0.5.0" — the revision that in fact reversed the raise. Rewritten to state the floor, its reversal history, D3's consumer rule and PLAT-02's principle. Its contract references advance from 0.5.0 to 0.9.0, and its Swift 6.4-minimum rule becomes the 6.2 minimum with 6.4 qualified.
- `MIGRATION.md`, the consumer-facing guide, told application maintainers to expect "Swift 6.4" and "All 27.0" three days after D3 decided they must raise to exactly 26.0. Corrected, restated against contract 0.9.0 rather than 0.4.0, and its optional-products row now carries the POL-05 dispositions instead of "retain or explicitly defer".
- `README.md` and `IMPLEMENTATION.md` described the OS 27/CLI record as the current qualification and as superseding the OS 26 decision. Both now draw the distinction the 0.5.0 revision actually drew: its platform claims are superseded history, its CLI content is current. `Scripts/README.md` claimed `validate.sh` requires one pinned preview-Xcode build, which 0.5.0 relaxed to accepting Swift 6.2 or 6.4; corrected to match the script it documents.
- `Documentation/Engineering/OS27CLI/` and the OS 27 entries in `HISTORY.md` are untouched: they are the historical record of what was decided and reversed, and POL-08 keeps superseded evidence rather than rewriting it. The deliberate `@available(macOS 27, *)` explanation in `Sources/SwiftJLI/Image.swift` is also untouched; it documents why those APIs are avoided and is correct as written.
- Verified on Apple Swift 6.2.3 (Xcode 26.2), debug and release: `swift build` and `swift test` pass with 35 tests; `Scripts/test-cli.py` passes 107 process checks including staged manual install and rendering; the corrected example builds and runs. `Scripts/validate.sh` fails at its `swift-package-help` step on this toolchain, identically on the unmodified tree, so that failure is pre-existing and unrelated to this change; under POL-08 it is an unexecuted gate, not a pass. Continuous integration remains blocked by the Actions billing lock. No codec capability, source move, release or tag is added.

## Milestone 2 pin and the contract 0.8.0 item 5 reconciliation — 23 September 2026

- Recorded the two decisions contract 0.9.0 permits before the continuous-integration precondition is met. Neither moves any source, and the line 0.9.0 draws — adding predecessor codec implementation or codec test files here — is not crossed.
- **Closed the foundation's open provenance question.** HISTORY.md recorded on 17 September that the inspected snapshot `9f1c6eb6` and the `v0.5.0` tag were separate references and did not assert they resolved to the same commit. Resolved: annotated tag object `a7a9bdde` dereferences to commit `9f1c6eb6`. They are the same commit. The 17 September entry stands as written.
- **Milestone 2 pins commit `0a4ded0b0b2e8e38127f4f302b286e74ee352474`**, not the last stable tag. The two commits between `v0.5.0` and that revision are twelve files of shared-storage work: borrowed-destination decode and borrowed-source encode paths that honour the caller's row stride and never touch inter-row padding, an internal geometry-only `JLIImage` initialiser, and 268 lines of contract image-layer tests. Contract 0.6.0 named this codec the clearest instance of the public image type obstructing caller-owned storage; these commits answer that finding, and the older tag would discard them. `v0.6.0-rc.1` is unpromoted, so the pin is a commit rather than a tag and is re-recorded if the final release carries more.
- **The item 5 reconciliation resolved on provenance.** At the pin, `Sources/JLISwift/Contract/` declares 159 public declarations against this repository's 153, with 151 shared. All eight predecessor files carry MIT SPDX identifiers inside an Apache-2.0 repository, and four of the six overlapping files are byte-identical to this repository's apart from that one line. The successors were MIT until 0.8.0 relicensed them on 22 September and the layer landed in JLISwift on 20 September, so it is a copy of the Milestone 1 types taken while they were MIT. The copies are retired; this repository's originals stand.
- `Image.swift` and `ImageStorage.swift` are the only substantive divergence, and it is entirely a consequence of the predecessor's floor: `OwnedImageStorage` and `ImageDestination` are `@unchecked Sendable` behind an `NSLock` there because `Synchronization.Mutex` needs macOS 15 and JLISwift ships at macOS 14. At the 26.0 floor here that justification is gone, so retiring the copies removes two unchecked annotations rather than importing them, which is what AGENTS.md requires.
- `BorrowedPlane.swift`, `ContractCodec.swift`, the codec-side shared-storage changes and `ContractImageLayerTests.swift` have no successor counterpart and migrate. Migrating files are normalised to the Apache-2.0 identifier under POL-07 as amended by 0.8.0; this is in-house code, not a third-party notice, and published predecessor tags keep their original texts.
- Recorded as limits rather than glossed: the predecessor's public `JLIImage` initialiser still rejects any buffer that is not the packed frame size, so that obstacle is worked around internally rather than removed and its removal remains successor work; and the predecessor's own test baseline at the pin is **not** established here, which TEST-04 requires and the CI precondition still gates.
- Verified that the pin changes no public API a consumer maps: the public declarations of `JLIImage`, `JLIDecoder` and `JLIEncoder` are identical at `9f1c6eb6` and `0a4ded0`. Evidence gathered by reading the predecessor through the GitHub API on 23 September 2026; no predecessor source was added to this repository and nothing was built or tested from it. Actions billing remained locked. No codec capability, source move, release or tag is added.

## Linux reentrancy guard on owned storage — 23 September 2026

- `OwnedImageStorage.locked(_:)` refused a reentrant or competing borrow solely by testing whether `Mutex.withLockIfAvailable` returned `nil`. Swift's Linux implementation **traps on same-thread reacquisition** instead of returning `nil`, so on Linux that refusal was not a refusal: `Tests/SwiftJLITests/OwnershipTests.swift`'s `reentrantLeaseOperationsRejectWithoutDeadlocking()` makes four reentrant calls inside an active borrow, and every one reaches that path.
- Added an `Atomic<Bool>` checked before the mutex, so a reentrant call is rejected with `storageUnavailable` without reaching the lock. macOS behaviour is unchanged — the same error is raised, one step earlier — and the concurrent, different-thread case still resolves through `withLockIfAvailable` as before.
- Not found here. SwiftJ2K's Milestone 4 Linux run found it and fixed its own copy of this type the same way; this repository's Milestone 1 types and SwiftJ2K's share an origin, so the defect was shared too. Contract 0.9.0 anticipates exactly this transfer between repositories, though it expected the SwiftJLS pilot to be the source.
- **This is a latent defect that this repository's own gates could not have caught.** The workflow runs `ubuntu-24.04` and `ubuntu-24.04-arm` jobs that exercise it, and no run has ever executed: Actions billing has been locked since before the workflow was written, verified again on 23 September 2026 with `steps=0` on every job of the most recent runs here and in SwiftJ2K.
- Verified on Apple Swift 6.2.3 (Xcode 26.2): `swift build` and `swift test` pass with 35 tests, including the reentrancy and concurrent-borrow cases. **The Linux behaviour this change exists for is unverified here**, because no Linux toolchain or runner is available to this work; the fix rests on SwiftJ2K's executed Linux evidence and on matching the implementation it proved. Under POL-08 that Linux path is an unexecuted gate, not a pass.

## `validate.sh` runs to completion again — 23 September 2026

The repository's own validation script had not run to the end on an accepted toolchain. It failed at its third command, and behind that failure were four more. Each is fixed or explicitly gated; the script now completes on Swift 6.2.3 and reports three unexecuted gates rather than a false pass.

- **`swift package <options> --help` is rejected.** `swift package` is a container command: Swift Argument Parser accepts `--help` on it only when nothing precedes it, and once any option is given it is looking for a subcommand and answers "Unknown option '--help'". The script passed its full option set first, so this could never have worked. It now uses the `help` subcommand, whose output is byte-identical and which works in every form.
- **SBOM generation does not exist before Swift 6.4.** Neither `swift build --sbom-spec` nor `swift package generate-sbom` is present on 6.2, which contract 0.5.0 keeps as an accepted toolchain, so the check failed the whole run on a toolchain the script is meant to accept — the same fault the 0.5.0 relaxation recorded at the top of that file was written to remove. The capability is now probed; when absent the run records an unexecuted gate under POL-08 and continues.
- **`swift test --maximum-repetitions` does not exist before Swift 6.4 either.** Rather than skip the check, the run now repeats the filtered selection that many times as separate executions, each validated and logged individually. The five repetitions of the eleven ownership, lifetime and cancellation cases executed and passed.
- **The Swift Build engine cannot build this package on a case-insensitive filesystem.** Swift Build names each target's intermediates directory after the target, and the library module `SwiftJLI` and the CLI product `swiftjli` differ only in case, so on macOS's default filesystem they are one directory: the two targets overwrite each other's dependency files and the compiler fails with "unable to open dependencies file". Verified directly — the filesystem is case-insensitive, the library alone always builds, anything including the executable always fails, and after a failed build only one of the two directories exists. Renaming either name is a contract decision under API-01 and CLI-01, so the script records the substitution rather than making one: it falls back to the native engine and reports `requested_build_engine` and `build_engine` separately.
- **The generated fresh consumer was pinned above the package it consumes**, at `swift-tools-version: 6.4` and `.macOS(.v27)`, so it could not resolve on the accepted toolchain. This is the same reversed-baseline defect corrected elsewhere on 23 September; the earlier sweep missed it because the manifest is built from a Python string and spells the floor `.v27` rather than `27.0`. Now 6.2 and 26.0, matching the package.
- **Unqualified `Encoder` and `Decoder` in the CLI.** `Sources/SwiftJLICLI/main.swift` referred to `Encoder.capabilities` and `Decoder.capabilities`. Those names are also the standard library's `Codable` protocols, so the moment the file's `import SwiftJLI` is not in effect they bind to those instead — which is what the Swift Build engine does, compiling `main.swift` as part of module `SwiftJLI` and reporting "type 'any Encoder' has no member 'capabilities'". Both are now qualified as `SwiftJLI.Encoder` and `SwiftJLI.Decoder`, which MIGRATION.md already asks consumers to do. This was a latent correctness bug, not only a build failure.
- Open gates are now printed at the end of a run. One that only ever reaches `report.json` is easy to read as a pass, and POL-08 turns on that difference.
- Verified on Apple Swift 6.2.3 (Xcode 26.2): `Scripts/validate.sh` completes with `status: passed_requested_checks`, 23 commands, 35 declarations executed and passed in debug and release, 11 declarations passed in each of five repetition iterations, and three recorded unexecuted gates — Swift Build coverage, SBOM generation and fresh URL-based consumer resolution. `swift test` passes 35 tests and `Scripts/test-cli.py` passes 107 process checks. The shared contract documents are unchanged. **Swift 6.4 remains unexercised here**: no 6.4 toolchain was available, so the `in_process` repetition path, the SBOM path and the Swift Build path are written but unexecuted.

## Executable renamed to `swiftjli-cli` — contract 0.10.0, 23 September 2026

- The diagnostic CLI is now **`swiftjli-cli`**. `swiftjli` differed from the library module `SwiftJLI` by case alone, and Swift Build names each product's intermediates directory after the product, so on a case-insensitive filesystem — the macOS default — the library target and the executable product resolved to one directory and overwrote each other's dependency files. Every build including the executable failed with "unable to open dependencies file"; the library alone built, which is why it stayed hidden.
- Measured before and after on Apple Swift 6.2.3: the filesystem probe reports case-insensitive; `--product SwiftJLI` succeeded every time and any build including the executable failed every time; after a failure only one of the two directories existed; renaming the **product** alone fixed it, and renaming the **target** alone did not, which is what identifies the product name as the cause. After the rename the Swift Build engine builds the whole package and three distinct directories exist.
- Not a new class of fault. `Documentation/Engineering/Swift64/RemoteConsumer/InitialDirectoryIdentityCollision/` already records the same case-only difference breaking URL-based consumer resolution with "product 'SwiftJLI' required by package 'swiftjli' not found in package 'SwiftJLI'".
- **CLI-01 is amended and the shared contract advances to 0.10.0.** Executable names become `swiftj2k-cli`, `swiftjls-cli`, `swiftjxl-cli` and `swiftjli-cli`, and no executable name may differ from a target or module name in the same package by case alone. `SUITE_POLICY.md`, `CLI_CONTRACT.md` and the SHA-256 manifest advance together. The library module name is unchanged: it is public API under API-01 and is not what moves.
- **The four repositories are out of step until this is mirrored.** SwiftJLS, SwiftJXL and SwiftJ2K collide identically and each needs this document, `CLI_CONTRACT.md` and its own rename. Each repository's byte-identity job compares its own documents to its own manifest, so this drift is invisible to CI and has to be closed deliberately.
- Renamed with the binary: `ManPages/swiftjli-cli.1` (page, title and body), the installer's tool name, the CLI guide, and the tool name the executable reports in `--help` and in the JSON capabilities payload.
- `Scripts/validate-swift64.py`'s engine guard now detects the real condition — two **distinct** manifest spellings that are equal when case-folded — rather than assuming every case-insensitive filesystem fails. A package reusing one spelling for its package, product and target is not a collision, which the first form wrongly flagged.
- Removing the fallback exposed a second, unrelated limitation the fallback had been hiding: on Swift 6.2.3 `swift test list` under the Swift Build engine returns its build log and **no test identifiers at all** — 35 under the native engine, 0 under swiftbuild — so every test gate would have had nothing to run. The engine is now probed once before anything is built with it, since the build and test gates share a scratch directory per label and cannot change engine midway. Whether a later toolchain enumerates them is not asserted; the probe measures and records.
- Verified on Apple Swift 6.2.3 (Xcode 26.2): `swift build` and `swift test` pass with 35 tests; `Scripts/test-cli.py` passes 107 process checks against the renamed binary, including staged manual install, update and rendering; `Scripts/install-cli.sh --destdir` stages exactly `bin/swiftjli-cli` and `share/man/man1/swiftjli-cli.1`; `Scripts/validate.sh` completes with `status: passed_requested_checks`, `case_folded_name_collisions: []`, 35 declarations passed in debug and release and 11 in each of five repetition iterations; the shared documents match their regenerated manifest. No library API, ownership, precision or fidelity semantics change, and no codec capability, source move, release or tag is added.
