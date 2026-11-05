# Derived release-product SBOM qualification

**Passed for both `SwiftJLI` and `swiftjli-cli` at shipping revision
`f548e5048e5c71204c2a2ec4036bf66c4f040285`.** These are separately labelled,
reproducible derivatives of build-associated SwiftPM output. The original
generator files remain byte-for-byte unchanged and retain their failures.

| Product | Derived outputs | Validation |
| --- | --- | --- |
| SwiftJLI library | [SPDX 3.0.1](library/spdx.derived.json), [CycloneDX 1.7](library/cyclonedx.derived.json), [receipt](library/receipt.json) | Both official JSON Schemas pass with zero findings; official SPDX OWL/SHACL validation conforms with no warnings allowed. Reference/identity/licence checks pass. |
| swiftjli-cli executable | [SPDX 3.0.1](cli/spdx.derived.json), [CycloneDX 1.7](cli/cyclonedx.derived.json), [receipt](cli/receipt.json) | The same structural, SPDX semantic and reference/identity checks pass against the separate CLI-associated build output. |

The library's original `--product SwiftJLI --sbom-filter all` does **not** identify
the executable product. Separate [CLI generation](../cli-raw/report.json) used
the same clean, genuinely fetched f548 checkout, Apple Swift 6.4.2, explicit
Swift Build, release configuration and two jobs, reusing its existing build
cache. Both CLI generation commands exited zero. The raw CLI SPDX still fails
two schema records, while raw CycloneDX passes its schema; [validation exit 1](../cli-raw/schema-validation-command.json)
is retained. The new CLI binary's hash is separately recorded; no test execution
or byte identity with the previously tested CLI binary is inferred from this
SBOM-only build.

## Exact corrections and supplemental inventory

[derive.py](derive.py) is pinned by SHA-256 in each receipt. Complete before/after
transformations are retained for the [library](library/transformations.json)
and [CLI](cli/transformations.json). They:

- Rename the unsupported SPDX package-version field to `software_packageVersion`;
  use `software_packageUrl` for the package's canonical source URL.
- Correct the SPDX generator CreationInfo's `specVersion` from tool version
  `6.4.2` to specification version `3.0.1`, retaining the tool version separately.
- Correct the Swift package URL using the fetched GitHub host, organisation,
  repository and exact revision. A product is not a separately resolvable Swift
  package: its invalid generated purl is retained in a comment/property, while
  the product's original ID, name, source revision and source link are preserved.
- Retain CycloneDX's root product once, in metadata, removing only the identical
  duplicate definition. Dependency references continue to resolve. Derived BOM
  identity/version and helper provenance distinguish the derivative from raw
  generation.
- Add source-backed Apache-2.0 declarations for in-house code and separately
  inventory the unchanged embedded sRGB2014 ICC profile under its own terms.
  The fixture's 3,024 bytes, SHA-256 and embedded Swift byte array agree. The
  generator's existing tool-licence relationship is corrected to identify a
  software tool package, rather than its creator Agent.

These mappings follow SPDX's [Package properties](https://spdx.github.io/spdx-spec/v3.0.1/model/Software/Classes/Package/),
[specVersion meaning](https://spdx.github.io/spdx-spec/v3.0.1/model/Core/Properties/specVersion/)
and [relationship types](https://spdx.github.io/spdx-spec/v3.0.1/model/Core/Vocabularies/RelationshipType/),
the pinned [Swift package URL definition](inputs/official/swift-definition.json),
and [CycloneDX 1.7](https://cyclonedx.org/docs/1.7/json/). The governing
[ICC profile terms](https://registry.color.org/profile-library/) remain separate
from the repository licence. Original licence/notice files are retained under
`inputs/source/`; third-party validation artefact licences are recorded in
[the shared schema notice](../../schema-licences/README.md).

The [library supplement](library/supplement.json) records **17** native load
commands observed in the qualified independent consumer. The [CLI supplement](cli/supplement.json)
records **21** load commands from its separately built executable. Both identify
the inspected binary hash, system/framework install names, weak links, linker
versions, host OS and SDK. Those linker versions are not independently established
runtime package versions. Native library licences are not guessed. No complete
transitive Apple SDK/runtime inventory is claimed, and a consumer's full linkage
is not attributed exclusively to SwiftJLI. These platform-provided components
are not represented as bundled copies or external SwiftPM packages.

## Reproduction and preservation

The recorded validator uses `jsonschema 4.25.1`, `referencing 0.37.0`,
`pyshacl 0.30.1`, `rdflib 7.1.4` and `packageurl-python 0.17.6`. Full dependency
versions, official schema/model/context hashes and setup commands are in
[inputs/receipt.json](inputs/receipt.json). Validation uses retained schema and
context bytes; it does not fetch an unrecorded context during the checks.

Use the isolated Python interpreter recorded in that receipt, or recreate its
pinned environment, then select a **new** output directory:

```sh
python derive.py --evidence /absolute/final-consumer-sbom \
  --inputs /absolute/final-consumer-sbom/derived/inputs \
  --product SwiftJLI --output /absolute/new/library-derived
python derive.py --evidence /absolute/final-consumer-sbom \
  --inputs /absolute/final-consumer-sbom/derived/inputs \
  --product swiftjli-cli --raw-sbom /absolute/final-consumer-sbom/cli-raw \
  --output /absolute/new/cli-derived
```

[Reproduction review](reproduction-review.json) replays both derivations and
matches all eight SBOM/supplement/transformation outputs byte-for-byte. Both
existing-output attempts refuse with exit 2; all 44 protected files remain
unchanged. Exact final commands are in each product's `execution.json`.
The earlier helper ICC-literal parsing failure, first successful library-only
derivation and its executed helper, plus the interrupted licence-download
attempt are retained separately. They are development receipts, not replacement
release-product evidence.

## Gate disposition

This closes the fixable **usable build-associated package/product SBOM
conformance** gap for the two named f548 products: structural validation,
SPDX's required semantic validation, identity/reference checks and applicable
in-house/embedded-asset licence evidence are present. This is an engineering
acceptance assessment of the explicitly scoped derivatives, not a claim that
SwiftPM's generator is fixed or that a stable release has been published.

The [historical Swift 6.4 record](../../../../../Engineering/Swift64/README.md)
remains unchanged. Its demand for schema and semantic validation is now met by
the separately identified derivatives, while raw-generator defects remain
reproducible. A future release with different shipping bytes, build products or
platform packaging must regenerate and revalidate its own documents. Full Apple
SDK/runtime inventory, unrelated platform qualification, fuzz/performance,
device and reporting-channel gates are not waived by this result.
