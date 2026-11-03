# Milestone 5 — remote consumer and build-associated SBOMs

**Historical pre-fix record.** The completed refresh for shipping candidate
`f548e5048e5c71204c2a2ec4036bf66c4f040285` is in
[final-consumer-sbom/README.md](final-consumer-sbom/README.md). It preserves the
same consumer pass and explicit SBOM producer limitations. The original
`8ae2762` evidence and reproduction below retain their own pin.

Assessed 3 November 2026 against immutable candidate
`8ae2762710d6279cd92222f5bb5ca95f042f694e`, suite policy **0.10.0**.
The 46 shipping Swift source hashes match the 3 November optimisation snapshot
`5351088d3bb4630a32de6509e4d62210ad14aaa0`. This evidence supplements that
snapshot without relabelling its earlier test runs.

## Fresh remote consumer — passed

A new package and empty scratch/configuration/cache directories under
`/private/tmp` resolved **https://github.com/raster-labs/SwiftJLI.git** at the
exact candidate revision. Dependency caching was disabled. Git system/global
configuration was disabled for the run, avoiding local URL rewrites; the
manifest contains no local-path dependency. The resolved graph contains only
SwiftJLI. The initial fetched checkout was clean.

Apple Swift **6.4.2** (`swiftlang-6.4.2.1.9`,
`clang-2100.4.1.1`), selected through
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, built with the
explicit **Swift Build** engine and **two jobs**. Clean and incremental consumer
builds passed in both debug and release, and both resulting executables exited
zero. This compiles the library as an external dependency. It is not another
execution of the full library test suite or proof on Swift 6.2 or another OS.
The consumer manifest retains Swift tools 6.2 and macOS deployment minimum 26.0;
the host OS and exact Xcode build are in the retained logs.

The preserved consumer exercises exact predictive samples, inspection,
allocating and caller-destination decode, allocation identity and declared copy
reports, progressive 12-bit storage/fidelity, explicit raw-float preview and
normalised-float input, XYB/sRGB interpretation, and explicit RGBA/YCbCr/greyscale
conversion. These assertions are consumer acceptance, not independent allocator
telemetry or an independent JPEG oracle.

[Commands, exit codes, source/binary hashes](consumer/report.json),
[URL manifest](consumer/Package.swift), [resolved pin](consumer/Package.resolved)
and [consumer source](consumer/main.swift) identify the executed artefacts.
The source was reused from the previously retained full-profile consumer; only
its manifest revision changed. This is revision-pinned consumption, not
semver-tag resolution, a stable release or application cutover.

## Build-associated SBOMs — generated, producer limitations remain

Both commands used `xcrun swift build --build-system swiftbuild -j 2 -c release
--product SwiftJLI --sbom-spec spdx|cyclonedx --sbom-filter all`, with explicit
package, scratch and output directories recorded in [the report](sbom/report.json).
The build source was the clean, freshly fetched checkout above, not the changing
Milestone 5 working tree. Each generation command exited zero. Raw outputs are
retained unchanged and identify the exact candidate without a `modified` suffix.

The producer could not find its schema bundle and skipped validation. Independent
validation then used `jsonschema 4.25.1`, `referencing 0.37.0` and recorded official
schemas: SPDX 3.0.1's versioned URL, and CycloneDX specification commit
`1ce97b2a7b8cf2429da248560d2aa671c6bce74a`. Download URLs, raw schema hashes,
compressed retained bytes and validator dependency versions are recorded in
[schema setup](sbom/schema-setup.json).

| Format | Independent JSON Schema result |
| --- | --- |
| CycloneDX 1.7 | Passed; zero findings. |
| SPDX 3.0.1 | Failed; graph records 8 and 9 contain unsupported `externalUrl` and `software_internalVersion` properties. |

The independent validator exited **1** because SPDX failed. The raw findings
match the previously recorded producer discrepancy; they are not removed from
the generated document or represented as a successful qualification. See
[schema results](sbom/schema-results.json) and
[exact validator command and exit](sbom/schema-validation-command.json).

[Separate field inspection](sbom/field-audit.json) confirms both SBOMs identify
the candidate and records CycloneDX's repeated `swiftjli:SwiftJLI` `bom-ref`
between its component list and metadata component. The generated CycloneDX core
product also lacks a licence field. A JSON Schema pass does not establish full
semantic conformance. Neither generated package graph inventories Foundation,
Synchronization, the Swift runtime or the Apple SDK. Repository licences,
fixture notices and exact compiler/SDK evidence remain separate obligations.

## Reproduction and boundaries

From the repository root, choose a fresh evidence directory:

```sh
python3 Documentation/Migration/Qualification/Milestone5/consumer-qualify.py --revision 8ae2762710d6279cd92222f5bb5ca95f042f694e --evidence /absolute/new/m5-consumer-sbom
python3 Documentation/Migration/Qualification/Milestone5/sbom-prepare-schemas.py --evidence /absolute/new/m5-consumer-sbom/sbom
```

Then use the isolated `validatorPython` recorded in `sbom/schema-setup.json` to
run `sbom-validate.py --evidence /absolute/new/m5-consumer-sbom/sbom`; the expected
status for the retained producer is exit 1, not a successful SPDX result. Run
`sbom-audit.py` with the same evidence argument for the separate field audit.
The retained commands show the exact executed paths and outcomes. Large build
trees and binaries stay outside the repository.

After the completed runs, the schema and field-audit helpers gained guards
rejecting an existing result file. This changes reproduction output handling
only; the raw SBOMs, completed receipts and validation results remain unchanged.
[The helper review](sbom/helper-safety-review.json) records pre/post-change
script hashes and verifies rejection without modifying retained evidence.
The consumer helper now also requires an explicit immutable `--revision` for
later candidates. Its originally executed revision-specific copy is preserved
as [consumer-qualify-executed-8ae2762.py](consumer-qualify-executed-8ae2762.py);
the original receipts remain unchanged.

No shipping source, contract, stable tag or external repository was changed.
Device qualification, remaining platform/security/fidelity gates, and any real
DICOMKit consumer integration are not inferred from these results.
