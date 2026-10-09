# SwiftJLI — staged implementation instructions

Read AGENTS.md and every common contract document first. Milestone 1 implements API shapes and owning storage; see [executed evidence](Documentation/MILESTONE1.md). Later milestones require an owner-assigned implementation task. Follow the common contract when predecessor conventions differ. Maintain performance, reliability and security together.

## Verified status — 9 October 2026

[PR #19](https://github.com/raster-labs/SwiftJLI/pull/19) merged the codec migration
and deadline-overflow correction into main as `a967d27`. The 13-job CI matrix
passes at its source revision `a1920c7`; source, tests, package, scripts and workflow
are unchanged in the merge commit. The milestones below remain the plan of record,
not a claim that every release gate has passed.

| Scope | Current disposition |
| --- | --- |
| Milestones 1–2: API/storage foundation and native migration baseline | Implemented; source inventory, provenance, predecessor comparisons and independent JPEG oracle evidence retained. |
| Milestone 3: caller storage and first suite pair | Implemented; shared storage/copy/lifetime checks and SwiftJ2K ↔ SwiftJLI integration evidence retained at their recorded revisions. |
| Milestone 4: profiles and qualification | Supported codec profiles and CI platform matrix implemented; performance acceptance and physical Watch resource qualification remain open. Unsupported combinations reject explicitly. |
| Milestone 5: release preparation | Consumer, documentation and provenance evidence present; stable-release acceptance remains open. No stable tag or downstream cutover is established. |
| Auxiliary products and CLI payload commands | Explicit I1–I3 dispositions below remain in force; deferred work is not claimed as implemented. |

The [acceptance ledger](Documentation/Migration/ACCEPTANCE.md) is authoritative
for current evidence and remaining gates. Historical measurements are not relabelled
as runs against the merged revision.

## Source and destination

Predecessor: [Raster-Lab/JLISwift](https://github.com/Raster-Lab/JLISwift). Target module/product: `SwiftJLI`. Target CLI: `swiftjli-cli`. Intended first stable library version: `1.1.0`.

**Milestone 2 pinned revision: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.** Selected and recorded 23 September 2026; see [the pin record](#milestone-2-pinned-predecessor-revision) below for the resolution evidence and why this revision rather than the last stable tag.

The documentation foundation inspected `9f1c6eb609fe6f26498db82b13df6b305630a374` and observed `v0.5.0` as the highest stable-shaped tag, recording them as separate references that it did not assert resolved to the same commit. They do: the annotated tag `v0.5.0` (`a7a9bdde1b859a4208f0f8c00e4806cd0e5bbaeb`) dereferences to commit `9f1c6eb6`. That question is now closed.

Do not migrate code from moving main without recording the selected revision. Reproduce relevant source tests and inspect source-level capabilities. Existing test totals and benchmark claims are historical, not successor acceptance evidence.

[MIGRATION.md](MIGRATION.md) describes the consumer-side upgrade from JLISwift, with current API mappings and deferred features. Update it as each assigned milestone adds qualified capabilities; its staged cutover checklist supplements the implementation gates below.

## Milestones and exit evidence

| Milestone | Work | Exit evidence |
| --- | --- | --- |
| 1 — contract feasibility | Establish Swift 6.4 package, independent local API/owning-memory types, descriptor validation and safe adapter experiment; no codec algorithm migration | Compiling equivalent public calls, lifecycle/race/error tests, standalone consumer build and contract issues resolved explicitly |
| 2 — migration baseline | Inventory predecessor subsystems/products; select and migrate the smallest native scalar lossless path with Apache-2.0/provenance reconciliation | Pinned predecessor comparison, independent decode/encode validation, exact sample/precision results, no new runtime codec dependency |
| 3 — shared-storage path | Direct final decode into caller storage and encode from compatible sealed storage | Required-sharing copy/allocation/lifetime proof; first suite pair or corresponding codec extension passes |
| 4 — feature/platform coverage | Extend supported modes/layouts, CLI, optional acceleration and all required OS/architecture paths | Capability matrix, codec-specific regressions, platform results, security and performance evidence |
| 5 — release preparation | Validate clean versioned consumption, docs/examples, migration guide, licence/fixture notices and release gates | Reviewed complete evidence; stable tag only after explicit release task |

Work one owner-assigned milestone at a time. Preserve internal algorithm names where helpful, but provide the agreed common public module surface. Do not publish a stable version or announce complete platform support while required gates are missing.


### Migration focus

- The predecessor has a native encoder and decoder. Do not treat this project as lossy encode-only or require an operating-system decoder. Preserve native decode on Linux and Apple platforms for the modes actually supported.
- `Sources/JLISwift/Encoder/JLIEncoder.swift` returns `[UInt8]`; `Sources/JLISwift/Decoder/JLIDecoder.swift` uses `decode(from:configuration:)`; `Core/JLIImage.swift` owns `[UInt8]`. Adapt these to common names, Data-based encoded results and owner-backed image views. Audit array conversions so they cannot hide full-frame copies.
- Distinguish baseline/extended/progressive lossy JPEG from SOF3 lossless JPEG. The common default lossless mode selects validated SOF3 with point transform zero. A nonzero point transform discards low-order information and cannot satisfy the sample-exact lossless declaration. High lossy quality is never advertised as lossless.
- Inventory supported 8/12-bit lossy modes and 2..16-bit lossless precision, predictors, sampling, colour models, restart markers and metadata. Explicitly reject unsupported requested combinations.
- The predecessor's float encode/decode scaling conventions differ in some paths. Document and reconcile them with the common descriptor; no silent [0,1] normalisation or raw-sample reinterpretation. Keep float support capability-specific until exact semantics are tested. Signedness metadata is not guaranteed by a generic JPEG output file.
- `Platform/AccelerateBackend.swift` uses vImage/DSP. Keep Apple adapters optional and implement/retain scalar correctness on Linux. Apple OS codecs may be test comparators, not required runtime substitutes.
- Inventory the optional JLIDICOM product separately. DICOM object parsing and metadata stay outside the new principal codec module. Preserve useful optional integration deliberately or record its deferral; do not silently pull DICOMKit into the core.

### Codec-specific tests

Test marker/table/scan bounds, Huffman and arithmetic bounds where applicable, restart handling, baseline/extended/progressive decode, 12-bit cases and SOF3 predictor/point-transform combinations. Independent validation must use an oracle that actually supports the selected JPEG mode and precision; an OS decoder supporting only baseline JPEG is insufficient for SOF3/16-bit gates.

Test full 16-bit unsigned extrema, component order, byte order, signed mappings only with explicit metadata, ICC/Exif size limits and float policy rejection. Compare lossless samples exactly; pin justified tolerances for lossy colour conversion/DCT paths. Preserve existing overflow, subsampling, configuration and Watch build reproducers.

### Initial codec delivery — Milestones 2–4

The following codec work follows Milestone 1 contract feasibility. It is not part of the first coding task. Migrate the scalar path in Milestone 2, prove shared storage in Milestone 3, and extend features/CLI/platform coverage in Milestone 4.

Build on the validated common surface to implement a native unsigned 16-bit lossless SOF3 shared-buffer path. Add the per-codec CLI and interop tests without assuming the predecessor benchmark executable is a general CLI. Join the suite transcode harness for lossless JPEG modes; retain lossy features as explicit options.


## Product dispositions (POL-05)

Decided 22 September 2026 under contract 0.8.0 §3, which requires this inventory before any subsystem is relocated. Measured at predecessor JLISwift `0a4ded0` with `swift package dump-package`. "Imports" counts files across DICOMKit, CompressionFamily, VoxeliaValidation, DICOMAdapter, RasterOneImage, OneImageViewer-iOS and telerad-dicom-viewer containing a top-level `import <module>`.

POL-05 requires every product to be explicitly **retained** (migrates, stays a public product), **adapted** (migrates with a changed shape — folded into the principal module, renamed, or re-expressed through the common API) or **deferred** (does not migrate for the first stable; stays with the predecessor through the maintenance window). Deferred is not deleted.

| Predecessor product | Files / lines | Imports | Disposition | Successor | Basis |
| --- | --- | --- | --- | --- | --- |
| `JLISwift` | 30 / 8,707 | 1 | Adapted — renamed | `SwiftJLI` | API-01 |
| ↳ `Sources/JLISwift/Contract/` | 8 / 989 | — | Adapted — folded in, mostly as retired duplicates | `SwiftJLI` | Contract 0.8.0 §5. The directory folds into the principal module rather than becoming a product, but six of its eight files are copies of this repository's Milestone 1 types and are retired rather than carried; only `BorrowedPlane.swift` and `ContractCodec.swift` have no counterpart here. File-by-file dispositions are in [the item 5 reconciliation](#reconciliation-of-duplicate-contract-surfaces-contract-080-item-5). |
| `JLIDICOM` | 3 / 1,305 | 0 | Deferred — retired | none | POL-05 keeps DICOM parsing in consumers, and `DICOMWindowRenderer` is windowing, which the memory contract excludes from the codec outright: "No windowing, VOI LUT, modality rescale, colour display conversion or automatic normalisation occurs in this contract." DICOMKit declares this product as a dependency and never imports it. |
| `JLIBench` (exec) | 10 / 2,616 | 0 | Deferred — dev tooling | none | TESTING keeps development-only tools outside the shipped dependency graph |

**Product list after migration:** `SwiftJLI` (library) and `swiftjli-cli` (executable).

### Decisions recorded with these dispositions

**I1 — DICOMKit's `JLIDICOM` dependency is dead and is dropped either way.** DICOMKit declares the product in its manifest and imports it in no source file, so it resolves and builds a product it never uses. Removing that declaration belongs in DICOMKit's separately assigned cutover task and does not depend on this migration.

**I2 — deferring `JLIBench` does not defer its fixtures.** Its `Regression/` corpus and `IdentityHashes.swift` are exactly the pinned predecessor corpus and bug reproducers TEST-04 requires to be carried forward. The fixtures migrate with the codec and keep their provenance records; only the executable is deferred.

**I3 — `swiftjli-cli`'s payload verbs are new work, not a migration.** The predecessor ships no codec CLI, only the `JLIBench` benchmark executable, so CLI-01's required surface cannot be migrated from anywhere. The first stable 1.1.0 ships the diagnostic CLI already present — help, version and capabilities — and `encode`, `decode`, `inspect`, `validate` are budgeted as new implementation in the CLI milestone rather than treated as part of the codec move.

## Milestone 2 pinned predecessor revision

Selected 23 September 2026 under contract 0.9.0, which permits "selecting and recording the pinned predecessor revision for Milestone 2" before the continuous-integration precondition is met. Recording a pin moves no source.

**Pin: commit `0a4ded0b0b2e8e38127f4f302b286e74ee352474`.** This is the commit the annotated tag `v0.6.0-rc.1` dereferences to, and it is also what the predecessor's `main` pointed at when the pin was taken.

| Reference | Annotated tag object | Commit | Tagged |
| --- | --- | --- | --- |
| `v0.5.0` | `a7a9bdde1b859a4208f0f8c00e4806cd0e5bbaeb` | `9f1c6eb609fe6f26498db82b13df6b305630a374` | 2026-06-12 |
| `v0.6.0-rc.1` | `28e4b962dad5f8fd54219c879d1c31b07ad11905` | `0a4ded0b0b2e8e38127f4f302b286e74ee352474` | 2026-09-21 |

`v0.6.0-rc.1` is an unpromoted release candidate, so the pin is recorded as the **commit**, not the tag. Promoting it is the predecessor's own release task (contract 0.8.0 item 6) and is not authorised here. If the final `v0.6.0` release carries further commits, this pin is re-recorded against that revision before Milestone 2 begins.

### Why this revision and not the last stable tag

`v0.5.0` is the obvious candidate — it is the last stable tag, it is the revision every provenance link in this repository already pins, and it is what DICOMKit consumes. It is nonetheless the wrong pin, because the two commits between it and `0a4ded0` are not incidental. They are twelve files, and they are the shared-storage work:

| Path | Change | Why it matters |
| --- | --- | --- |
| `Sources/JLISwift/Contract/` | 8 files added, 989 lines | The contract surface and its codec adapter |
| `Sources/JLISwift/Core/JLIImage.swift` | +32 | An **internal** geometry-only initialiser, so a shared-storage image can be described without samples |
| `Sources/JLISwift/Decoder/JLIDecoder.swift` | +93 −25 | A borrowed-destination decode path that honours the caller's row stride and never writes inter-row padding |
| `Sources/JLISwift/Encoder/JLIEncoder.swift` | +77 −13 | A borrowed-source encode path that never reads padding into the codestream |
| `Tests/JLISwiftTests/ContractImageLayerTests.swift` | +268 | The contract image-layer tests |

Contract 0.6.0 identified the caller-storage obstacle as the public image type rather than the codec interior, and named this codec the clearest instance of it. The commits above are the answer to exactly that finding. Pinning at `v0.5.0` would discard them and re-derive them here, against a predecessor baseline that no longer matches the source the tests were written for.

Two qualifications are recorded rather than glossed. First, the geometry-only initialiser is `internal` and the public `JLIImage` initialiser still rejects any buffer that is not the packed frame size, so the public-type obstacle contract 0.6.0 described is worked around internally, not removed; removing it remains successor work. Second, the predecessor's own test baseline at this pin has **not** been established here — TEST-04 requires reproducing it on a compatible platform and recording failures and skips, and that is Milestone 2 work that the continuous-integration precondition still gates.

## Reconciliation of duplicate contract surfaces (contract 0.8.0 item 5)

Recorded 23 September 2026. Contract 0.8.0 item 5 requires that where a migrated contract layer duplicates the Milestone 1 types already built here, one of the two is retired deliberately and the choice recorded, because "two parallel surfaces in one module are not an acceptable migration outcome". At the pin this is not hypothetical: `Sources/JLISwift/Contract/` declares 159 public declarations, `Sources/SwiftJLI/` declares 153, and 151 are identical when compared as normalised public declaration lines.

The duplication has a traceable cause. All eight predecessor contract files carry `SPDX-License-Identifier: MIT` inside an Apache-2.0 repository. The successors were MIT until contract 0.8.0 relicensed them to Apache-2.0 on 22 September 2026, and this layer landed in JLISwift on 20 September. Four of the six overlapping files — `CodecAPI.swift`, `Errors.swift`, `ImageDescriptor.swift` and `Options.swift` — are byte-identical to this repository's files apart from that one licence line. The predecessor's contract layer is a copy of this repository's Milestone 1 types, taken while they were MIT.

| Predecessor path | Disposition | Basis |
| --- | --- | --- |
| `Contract/CodecAPI.swift`, `Errors.swift`, `ImageDescriptor.swift`, `Options.swift` | **Retired** — the copy is dropped; this repository's file stands | Byte-identical but for the SPDX line; nothing to merge |
| `Contract/Image.swift`, `ImageStorage.swift` | **Retired** — this repository's file stands | Differ only in the concurrency bridge; see below |
| `Contract/BorrowedPlane.swift` | **Migrates** | No successor counterpart; the non-`Sendable`, non-owning borrow types the codec interior sees |
| `Contract/ContractCodec.swift` | **Migrates, adapted** | No successor counterpart; `JLIContractCodec` is the adapter that binds the contract surface to the codec |
| `Core/JLIImage.swift`, `Decoder/JLIDecoder.swift`, `Encoder/JLIEncoder.swift` changes | **Migrate** | The shared-storage paths; the reason for the pin |
| `Tests/JLISwiftTests/ContractImageLayerTests.swift` | **Migrates** | Contract-layer coverage, carried forward under TEST-04 |

**Why this repository's `Image.swift` and `ImageStorage.swift` win.** These are the only two files that diverge in substance, and the divergence is entirely a consequence of the predecessor's deployment floor. `OwnedImageStorage` and `ImageDestination` are `@unchecked Sendable` there, guarded by `NSLock` with a written proof, because `Synchronization.Mutex` requires macOS 15 and JLISwift ships at macOS 14 with consumers there. This repository's floor is 26.0, so the same two types use `Mutex` and are checked `Sendable`. The bridge is sound where it stands and unnecessary here: once the code sits at a 26.0 floor its entire justification is gone, and AGENTS.md requires a local written proof and lifetime/race tests for every unchecked annotation. Retiring the copies removes two unchecked annotations rather than importing them.

**Licence handling on migration.** The MIT headers are an artefact of the copy direction, not a third-party notice. This is in-house Raster Images code, and POL-07 as amended by contract 0.8.0 licenses this repository, its in-house source and its documentation under Apache-2.0. Files migrating from the predecessor are normalised to the Apache-2.0 identifier, and each migrated path records its source commit. This is not authority to alter any third-party notice, and the predecessor's published tags keep their original texts.

**What is not decided here.** This record settles which surface survives. It does not move any source: under contract 0.9.0 adding predecessor codec implementation or codec test files to this repository is the line that is not crossed until continuous integration executes and passes here, and the Actions billing lock was still in force when this was recorded.

## Required handover

Update CHANGELOG.md and migration provenance. Provide the exact commands, commits, fixture hashes and outcomes; report tests not run and why, unsupported cases, allocation/copy evidence and performance impact. Map each advertised feature to a test and capability entry. Keep DICOMKit/Voxelia source changes outside this repository task unless the owner separately assigns them.

## Owner-authorised CLI foundation

Before codec migration, the owner requested executable help, verbosity and UNIX manuals, and in the same contract revision (0.4.0) raised Apple floors to 27.0. The CLI authorisation stands; the floor raise does not. Contract 0.5.0 returned the Apple minima to 26.0 and the manifest minimum to Swift 6.2, and contract 0.9.0 confirmed 26.0. This bounded CLI foundation implements help/version/capabilities only; codec commands remain explicitly unavailable. See [CLI.md](CLI.md) and the [OS 27/CLI record](Documentation/Engineering/OS27CLI/README.md), whose platform claims are superseded history and whose CLI content is current. The later codec/CLI milestones still govern real payload operations.
