# Prepared-revision consumer and product SBOMs — 4 November 2026

**Passed for immutable revision `7739dba554cabebcc25e3593af3feb6ba27f8489`.**
This qualifies the prepared `1.1.0` metadata revision through its genuine GitHub
URL. It does not qualify stable-tag or semantic-version resolution, publish a
release, integrate DICOMKit, or complete the physical-device gates.

The [source receipt](consumer/source-identity.json) binds the clean fetched
checkout to all 46 shipping Swift files and `Package.swift`. Its 45 library
files and manifest match `f548e5048e5c71204c2a2ec4036bf66c4f040285` byte-for-byte.
The sole shipping difference is prepared CLI metadata in
`Sources/SwiftJLICLI/main.swift` (SHA-256
`d233714b13970668841e38cf027f679e405cbfc373b0476477977a44d58887f3`).
The fetched source and both inspected executables remained unchanged throughout
the product qualification.

| Check | Executed result |
| --- | --- |
| Fresh URL consumer | Clean and incremental debug/release Swift Build builds passed; both consumer executables exited 0. The resolved graph contains only SwiftJLI at the exact revision, without local paths or sibling dependencies. |
| Library and CLI build-associated generation | All four release generation commands exited 0 with `--sbom-filter all`; the CLI was selected independently with `--product swiftjli-cli`. Its `--version` returned `swiftjli-cli 1.1.0`. |
| Preserved raw SPDX 3.0.1 | Each product fails two schema records containing the known unsupported generator properties. Both validator exits of 1 are retained. |
| Preserved raw CycloneDX 1.7 | Both JSON Schemas pass; the duplicate root reference and missing product licence remain separately reported producer defects. |
| Derived library and CLI documents | All four official JSON Schema checks pass. Both SPDX documents conform to the retained official OWL/SHACL model, with warnings disallowed; identity, references, source revision, package URL and embedded ICC checks pass. |

[Consumer commands and results](consumer/report.json),
[product commands and results](product-qualification.json),
[library raw schema results](sbom/schema-results.json) and
[CLI raw schema results](cli-raw/schema-results.json) retain the distinct outcomes.
The selected toolchain is Apple Swift **6.4.2**
(`swiftlang-6.4.2.1.9`, Clang `2100.4.1.1`), Xcode **27.2 / 27B52**, macOS SDK
**27.2**, on arm64 macOS **27.0.1 / 26A434**. Every build explicitly uses
`--build-system swiftbuild -j 2`; the manifest retains tools 6.2 and Apple 26.0
deployment minima. This run does not qualify the minimum compiler or OS runtime.

The consumer checks predictive sample equality, allocating and caller-destination
decode, ownership/copy reports, progressive 12-bit output, explicit float
policies, XYB/sRGB and RGBA/YCbCr/greyscale conversion. These are finite public API
checks, not independent allocator, oracle, sanitizer or performance measurements.

## Derived outputs and scope

| Product | Outputs and receipt |
| --- | --- |
| `SwiftJLI` | [SPDX](derived/library/spdx.derived.json), [CycloneDX](derived/library/cyclonedx.derived.json), [receipt](derived/library/receipt.json), [supplement](derived/library/supplement.json) |
| `swiftjli-cli` | [SPDX](derived/cli/spdx.derived.json), [CycloneDX](derived/cli/cyclonedx.derived.json), [receipt](derived/cli/receipt.json), [supplement](derived/cli/supplement.json) |

The [adapted helper](helpers/derive-prepared.py) retains the previously reviewed
transformation rules, requires an explicit immutable revision and denies socket
connections during validation. [Its adaptation receipt](helper-adaptation.json)
identifies the unchanged historical helper and the executed new bytes.
[Library](derived/library/transformations.json) and
[CLI](derived/cli/transformations.json) records disclose every transformation.
The derivative corrects proven producer fields and references; it preserves raw
outputs, package/product identities and source revisions. SBOM package versions
remain source commit identifiers: the prepared `VERSION` file is not evidence of
a published `1.1.0` tag.

Current source licence, notice, ICC provenance/profile bytes and CLI metadata
are captured from the fetched revision in [the input receipt](derived/inputs/receipt.json).
Apache-2.0 covers in-house source; the embedded 3,024-byte sRGB2014 ICC profile
retains its separate terms. Reused official schemas, SPDX context/model and Swift
package-URL definition are hash-bound to their original acquisition records;
no validation context was downloaded during this run. The
[shared third-party schema/model notices](../../schema-licences/README.md) apply
to this record's exact unchanged copies: the four compressed schemas listed in
[library schema reuse](sbom/schema-reuse.json) and
[CLI schema reuse](cli-raw/schema-reuse.json), and the SPDX model/context and
Swift package-URL definition under [official inputs](derived/inputs/official).
Those manifests and the input receipt bind the copies to the licensed historical
bytes. Historical SPDX source-attribution limitations remain
explicit in that notice; no blanket Apache licence is asserted for the schemas.

The supplements identify 17 native load commands from the qualified release
consumer and 21 from the separate CLI binary. They record the exact binary hashes,
platform install names and weak links. Linker compatibility/current versions are
not runtime package versions. Complete transitive Apple SDK/runtime inventories
and their licences are not inferred from Mach-O metadata, and the consumer's
linkage is not attributed exclusively to SwiftJLI.

## Reproduction and preservation

The exact executed entry commands are in [consumer execution](consumer-execution.json)
and [product execution](product-execution.json); individual command arguments,
working directories, exits and log hashes are retained in their reports.
For a fresh run, select a new absolute evidence directory, run
`../../consumer-qualify.py --revision 7739dba554cabebcc25e3593af3feb6ba27f8489 --evidence NEW`,
copy this record's `helpers/` directory into `NEW/helpers/`, then run
`NEW/helpers/qualify-products.py` using the arguments in `product-execution.json`
with the new evidence path. Point `--historical` at the preserved
`../../final-consumer-sbom` directory. Use the retained validator interpreter,
or recreate its pinned packages from `validator-packages.stdout`.

The validator versions are `jsonschema 4.25.1`, `referencing 0.37.0`,
`pyshacl 0.30.1`, `rdflib 7.1.4` and `packageurl-python 0.17.6`.
[Fresh-output guard checks](guards/receipt.json) rejected all four attempts to
reuse completed outputs without changing any of 159 protected qualification
files or 206 historical files. The original f548 and earlier raw/derived records
remain untouched. [Independent read-only review](independent-review.json) checks
source, command, input, binary, transformation and output bindings. No full suite,
fuzz campaign, benchmark, new simulator/device
run, stable publication or shipping-source edit was performed here.

These results refresh usable build-associated SBOM conformance for the two
products at this prepared revision. A changed integration or shipping candidate
needs its own applicable evidence; the expanded Milestone 5 remains governed by
[the release-completion record](../README.md).
