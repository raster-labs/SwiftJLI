# History and provenance — SwiftJLI

## Documentation foundation — 17 September 2026

The owner chose four fresh repositories under Raster-Lab, with independent codecs, a common API and memory contract, MIT licensing and an optional adapter-based umbrella. The previous proposal for a new shared-foundation package, SwiftCompressionFamily 2.0.0, was superseded. The intended first stable release here is 1.0.0; no library version has been released or tagged by this foundation.

| Item | Recorded source |
| --- | --- |
| Predecessor | [Raster-Lab/JLISwift](https://github.com/Raster-Lab/JLISwift) |
| Default branch observed | main |
| Inspected source snapshot | [9f1c6eb609fe6f26498db82b13df6b305630a374](https://github.com/Raster-Lab/JLISwift/commit/9f1c6eb609fe6f26498db82b13df6b305630a374) |
| Highest stable-shaped tag observed | [v0.5.0](https://github.com/Raster-Lab/JLISwift/tree/v0.5.0) |
| Source-tree licence observed | Apache-2.0 |
| Successor licence | Apache-2.0, for owner-authorised in-house material (contract 0.8.0) |
| Inspection date | 2026-09-17 |

The tag and the inspected branch snapshot are separate references; this record does not assert they resolve to the same commit. Before migrating a tagged baseline, resolve annotated tags to commits and record the exact chosen SHA. The pinned snapshot above was read for documentation preparation; it was not independently built or regression-tested in this task.

## Migration provenance requirements

The coding agent must record source repository, commit, original path and successor path for each migrated subsystem, and distinguish copied/adapted in-house material from new implementation. Record retained tests, fixture licences and explicit product/feature dispositions. Keep predecessor bug history accessible through links. Do not import old tags, rewrite predecessor history or imply all historical commits have been relicensed.

The owner states the implementation is in-house and has authorised Apache-2.0 relicensing (contract 0.8.0; the foundation recorded this as MIT). Preserve accurate original copyright years and ownership. Audit any third-party dependencies, tools or fixtures separately. The root licence is not authority to remove another party's notices.

The originals are intended to become maintenance projects while new development moves here. No predecessor settings, README, branch, release, licence or archive flag was changed during this documentation preparation. Maintenance announcements and downstream DICOMKit/Voxelia migration are separate work.

## Swift 6.4 development upgrade — 19 September 2026

The owner assigned the successor upgrade before Milestone 2 and requested version increments. Starting from `62e9502082a90bbabedf3d554b58e6dc8356b30a`, the candidate requires Swift tools 6.4 in Swift 6 language mode, advances shared contract 0.2.1 to 0.3.0 and advances the unreleased 1.0.0 target to 1.1.0 (`1.1.0-dev.1` development identifier). Platform floors, public API signatures, licensing and codec milestone scope are preserved. This is not a release/tag. The [upgrade record](Documentation/Engineering/Swift64/README.md) keeps current evidence separate from the earlier historical reports.

## OS 27 and CLI foundation — 19 September 2026

Apple platform floors are 26.0; contract 0.5.0 reverses the 0.4.0 raise to 27.0, which no released SDK, toolchain or CI runner can currently validate. Development version 1.1.0-dev.2, common contract 0.5.0. The standalone `swiftjli` provides help/version/capabilities, five diagnostic levels and a matching section 1 manual installed/updated with the binary. Codec commands remain unavailable. Byte-order sample access uses explicit fixed-width integer conversion and does not raise the runtime floor. See [qualification and limitations](Documentation/Engineering/OS27CLI/README.md). Historical evidence and supplied documents remain unchanged.
## Apple floor restored to 26.0 — 20 September 2026

Contract 0.5.0 reverses the 0.4.0 raise of the Apple deployment floors to 27.0 and returns them to 26.0. Verification found that no generally available Xcode ships OS 27 SDKs, that no stable `macos-27` continuous-integration runner exists, and that Swift 6.4.0 rejects a 27.0 deployment target because its supported range ends at 26.5.x. Every OS 27 qualification claim was therefore unreproducible.

The raise was not an independent platform decision. Contract 0.4.0 adopted the OS-27-gated byte-order span overloads, and the floor moved so that they would compile. Contract 0.3.0 had already specified the correct treatment, explicit fixed-width integer endian conversion without raising the runtime floor, and that rule is restored. The compiler minimum returns to Swift 6.2 with Swift 6.4 retained as the qualified primary toolchain, because a manifest floor constrains consumer resolution and every current consumer resolves at 6.2.

Public signatures, ownership and fidelity semantics, milestone boundaries and Linux scope are unchanged. The OS 27 and Swift 6.4 records remain as history, marked superseded where they assert a platform baseline.

## Shared-storage rules refined from measurement — 20 September 2026

Contract 0.6.0 amends seven memory rules and adds one testing rule. Exploratory spikes ran the caller-storage question against all four predecessor codecs in both directions before any migration work, and every amendment comes from something those spikes measured or broke rather than from anticipated design.

The central finding reverses a standing assumption. `CopyPolicy.requireSharedStorage` is reachable in every codec, and each library reaches caller samples through exactly one stage, so pointing that stage at caller memory is small and local. What blocks the policy is the container each library exposes — `Data` per component, a packed `[UInt8]` with no row stride, a `[[Int]]` façade over an already-flat interior, or an initialiser that rejects any buffer that is not the packed frame size. A caller holding a padded plane cannot describe an image without first copying it. The `Image`/`ImageDescriptor` layer is therefore not packaging around working codecs; it is the Milestone 3 work.

This codec is the clearest instance of the public type being the obstacle. `JLIImage` holds a packed, immutable `[UInt8]` with a computed row stride, and its initialiser rejects any buffer whose length is not exactly the packed frame size, so a caller holding a padded plane cannot describe an image without first copying it. Workspace is `Int32` planes at twice the final frame.

Measured effects, all from a developer machine: live heap held after one JPEG 2000 decode fell from 16 MB in 6 blocks to 1 KB in 2 at 2048×2048, and for JPEG XL from 2 MB to nothing at 1024×1024; the JPEG 2000 output stage ran 9–35% faster writing the caller's plane; and on the encode side the copy a caller must make today costs 5.5 ms and 8 MB at 2048×2048 while the widening loop costs the same either way. Four defects surfaced during the work: inferred plane origins shearing padded multi-plane output, a shared encode that dropped its container wrapper and was caught only by comparing bytes rather than samples, a harness that bound an owner to storage released on the same line, and an address-sanitizer run reporting 100 MB live on a path holding nothing, which a probe traced to the sanitizer quarantining freed blocks.

The spikes are exploratory and are not proposed for merge into the predecessor repositories. No platform, milestone, release or CLI decision changes, and continuous integration remains blocked, so none of these results is a release gate.

## Decision D1 — codec libraries stay where they are, 20 September 2026

Contract 0.7.0 settles the programme's open architectural question. The shipping codec libraries are the existing repositories; the four contract repositories hold the shared documents, the reference implementation of the shared image layer and the cross-codec conformance harness. No codec source is relocated and nothing is deleted.

The Milestone 3 spikes decided it. All four codec interiors proved contract-capable through single-point changes, and the obstacle to caller-owned storage is the public image type rather than the codec, so the remaining work is additive and identical in size wherever it is done. Migration would have paid, on top of that identical work, the relocation of roughly 219,000 lines of codec source and 184,000 lines of tests together with fixtures and cross-codec oracles, with no continuous integration available to catch what such a move breaks. The contract repositories hold about 1,000 lines of source each, so little built work is given up; three in-house consumers already resolve the existing libraries by URL at pinned released versions, and none references a contract repository.

JLISwift keeps its codec, its 11,375 lines of source and its 5,647 lines of tests, and has no external package dependency at all. Its `JLIImage` initialiser, which rejects any buffer that is not the packed frame size, is the clearest single instance of the public type being the obstacle and is where its contract work starts. It is Apache-2.0 while this repository is MIT; see the note under POL-07. DICOMKit consumes it by URL.

Two matters are referred to the owner rather than assumed: the Apache-2.0 and MIT split between the existing libraries and the contract repositories, which POL-07 authorises resolving but which should be a deliberate choice; and the inventory and splitting of auxiliary predecessor products under POL-05. The decision rests on documentation evidence gathered on one machine and authorises no codec milestone or release.

## Decision D2 — codec libraries relocate here, 22 September 2026

Contract 0.8.0 supersedes Decision D1. The owner has reaffirmed the repository foundation v0.1.0 as the guidance for this migration and instructed that the codecs move into the successor repositories. Under document precedence rule 1 the owner's current explicit decision outranks a previous contract revision.

JLISwift relocates here: 11,375 lines of source and 5,647 lines of tests, with its fixtures and oracles. It has no external package dependency at all. Its `JLIImage` initialiser, which rejects any buffer that is not the packed frame size, is where its contract work starts. `JLIDICOM` and `JLIBench` need a POL-05 disposition. DICOMKit consumes it by URL.

The sequence is a final JLISwift release at v0.6.0, then relocation, then a first stable 1.1.0 here once the TEST-07 gates pass, then a maintenance window on the predecessor, then its archive. JLISwift is not renamed or deleted: this repository's HISTORY.md and MIGRATION.md pin its commits and source files by permalink, and those links are the provenance record.

D1's measurements are retained as the risk register rather than discarded. The continuous-integration objection is unresolved and becomes a precondition: the organisation's Actions billing remains locked, a re-run of JLSwift's CI on 22 September 2026 completed with `steps=0`, and no codec source moves before CI executes and passes here. This record authorises no codec milestone and no release.

## Contract 0.9.0 — floor decision and programme sequence, 22 September 2026

Decision D3 keeps the Apple deployment floor at 26.0 and places the cost of adoption on each consumer at its own cutover. DICOMKit consumes JLISwift from 0.5.0 at macOS 15 / iOS 18 / tvOS 18 / visionOS 2. JLISwift is the supported route for those consumers until they raise their floors and re-point, and it is archived only after the last of them has moved.

This repository is second in sequence, after the SwiftJLS pilot. The predecessor's current release candidate is v0.6.0-rc.1; its promotion is the predecessor's own release task and is not authorised here.

The continuous-integration precondition from 0.8.0 stands. Actions billing remained locked on 22 September 2026, so every workflow in the suite is written and unexecuted. No codec source moves here before CI executes and passes here.

## Milestone 2 pin and the item-5 reconciliation — 23 September 2026

Contract 0.9.0 permits selecting the pinned predecessor revision and recording the contract 0.8.0 item 5 reconciliation choice before the continuous-integration precondition is met. Both are now recorded in [IMPLEMENTATION.md](IMPLEMENTATION.md). Neither moves any source.

The foundation's open provenance question is closed. On 17 September 2026 this record noted that the inspected snapshot `9f1c6eb6` and the `v0.5.0` tag were separate references and did not assert that they resolved to the same commit, and instructed that annotated tags be resolved before a tagged baseline is migrated. Resolved on 23 September 2026: the annotated tag `v0.5.0` is tag object `a7a9bdde1b859a4208f0f8c00e4806cd0e5bbaeb` and dereferences to commit `9f1c6eb609fe6f26498db82b13df6b305630a374`. They are the same commit. The 17 September entry stands as written; this resolves it rather than amending it.

The pin is nonetheless **not** `v0.5.0`. It is commit `0a4ded0b0b2e8e38127f4f302b286e74ee352474`, which the annotated tag `v0.6.0-rc.1` dereferences to and which the predecessor's `main` pointed at when the pin was taken. The two commits between the last stable tag and that revision are the shared-storage work: a borrowed-destination decode path and a borrowed-source encode path that honour the caller's row stride and never touch inter-row padding, an internal geometry-only `JLIImage` initialiser that lets a shared-storage image be described without samples, and 268 lines of contract image-layer tests. Contract 0.6.0 named this codec the clearest instance of the public image type being the obstacle to caller-owned storage; these commits are the answer to that finding, and pinning at the older tag would discard them. The candidate is unpromoted, so the pin is recorded as a commit rather than a tag, and it is re-recorded if the predecessor's final v0.6.0 release carries further commits.

The reconciliation resolved itself once the duplication's cause was traced. All eight files of the predecessor's contract layer carry MIT SPDX identifiers inside an Apache-2.0 repository, and four of the six that overlap with this repository's Milestone 1 types are byte-identical to them apart from that one line. The successors were MIT until contract 0.8.0 relicensed them on 22 September 2026, and the layer landed in JLISwift on 20 September: it is a copy of this repository's types, taken while they were MIT. The copies are retired and this repository's originals stand. The two files that diverge in substance, `Image.swift` and `ImageStorage.swift`, differ only because `OwnedImageStorage` and `ImageDestination` are `@unchecked Sendable` behind an `NSLock` there — a documented bridge that exists because `Synchronization.Mutex` needs macOS 15 and JLISwift ships at macOS 14. At this repository's 26.0 floor that justification is gone, so retiring the copies removes two unchecked annotations rather than importing them. `BorrowedPlane.swift`, `ContractCodec.swift`, the codec-side shared-storage changes and the contract tests have no successor counterpart and migrate.

Two limits are recorded rather than glossed. The predecessor's public `JLIImage` initialiser still rejects any buffer that is not the packed frame size, so the obstacle contract 0.6.0 described is worked around internally rather than removed, and removing it remains successor work. The predecessor's own test baseline at the pin has not been established here; TEST-04 requires reproducing it and recording failures and skips, and that is Milestone 2 work which the continuous-integration precondition still gates. Actions billing remained locked when this was recorded.

## Executable renamed to `swiftjli-cli` — contract 0.10.0, 23 September 2026

The diagnostic CLI was `swiftjli`, which differs from the library module `SwiftJLI` by case alone. Swift Build names each product's intermediates directory after the product, so on a case-insensitive filesystem — the macOS default — the library target and the executable product resolved to one directory and overwrote each other's dependency files. Any build including the executable failed; the library alone built, so the fault survived unnoticed until the Swift Build engine was exercised. The same case-only difference is already recorded once in this repository's Swift 6.4 evidence, where a consumer checkout directory named `swiftjli` broke URL-based resolution.

The cause was isolated rather than guessed: renaming the product alone fixes the build and renaming the target alone does not. CLI-01 is amended accordingly and the shared contract advances to 0.10.0 — the four executables gain a `-cli` suffix, and no executable name may differ from a target or module name in the same package by case alone. Library module names do not change; they are public API under API-01.

The owner directed the rename after the alternative, leaving the defect in place behind the validation script's native-engine fallback, was recorded in contract 0.9.0's successor. SwiftJLS, SwiftJXL and SwiftJ2K carry the identical collision and the identical CLI-01 text, so the suite is out of step until this revision and their own renames are mirrored; each repository's byte-identity job sees only its own documents, so that drift is invisible to continuous integration.

Removing the fallback exposed a second limitation it had been hiding: on Apple Swift 6.2.3 the Swift Build engine enumerates no tests at all, against 35 under the native engine, so the validation script now probes the engine once before building with it and records the substitution. Continuous integration remained blocked by the Actions billing lock throughout, so none of this has been verified anywhere but a developer machine.

## Native codec migration checkpoint — 7 October 2026

The assigned migration now connects predictive lossless/bounded-error and 8/12-bit sequential/progressive DCT kernels to the common owning-storage API, with explicit fidelity/backend reporting. Pinned predecessor fixtures and native identity records are retained. This is an implementation checkpoint, not a release: advanced colour/float profiles, complete public corpus coverage, memory/performance qualification and the required platform matrix remain open. See [executed evidence and limitations](Documentation/Migration/STATUS.md).

## Codec implementation merged — 9 October 2026

[PR #19](https://github.com/raster-labs/SwiftJLI/pull/19) merged as
`a967d27bc5756fab8b7fe9db6eb302ff0645c362`. The migrated predecessor remains pinned
at `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Native predictive and DCT profiles,
explicit colour/Float32 policies, caller storage, bounded execution and retained
provenance are implemented. The final source revision `a1920c7` also fixes a
reviewed finite-deadline overflow without disabling cancellation or deadline checks.
All 13 jobs in CI 37900647193 pass at that revision; source/tests/workflow match
the merge commit. Earlier fuzz, interoperability, memory and performance evidence
retains its own exact revision rather than being relabelled as fresh execution.

Performance acceptance and physical Watch resource validation remain open.
JLIDICOM/JLIBench product deferrals and the separate CLI payload milestone remain
explicit. This merge does not publish a stable release, retire JLISwift or migrate
DICOMKit/Voxelia. See [the current ledger](Documentation/Migration/ACCEPTANCE.md).
