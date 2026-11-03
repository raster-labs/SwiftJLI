# Final-candidate consumer and SBOM qualification — 3 November 2026

Candidate **`f548e5048e5c71204c2a2ec4036bf66c4f040285`**, suite policy **0.10.0**.
The [subsequent derived-product record](derived/README.md) supplies schema- and
SPDX-semantics-validated library and CLI SBOMs, preserving the original producer
failures documented below. Independent review accepts that scoped conformance
gate; it does not claim the generator itself is corrected.

The source is fetched from its genuine GitHub URL into fresh isolated SwiftPM
directories. The resolved dependency graph contains SwiftJLI alone, pinned to
that immutable commit. Neither a local-path nor sibling-codec dependency is
used. The source differs from the earlier `8ae2762` qualification only in
`Sources/SwiftJLI/NativeExecution.swift`, whose SHA-256 is
`695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`.

**Consumer passed.** Explicit Swift Build, Apple Swift 6.4.2 and two build jobs
completed clean and incremental debug/release builds. Both resulting consumer
executables exited zero. The maintained consumer covers predictive sample
equality, allocating/caller destination decode, public ownership/copy reports,
progressive 12-bit output, float policies, XYB/sRGB and RGBA/YCbCr/greyscale
conversion. These are finite consumer checks, not independent allocator or
JPEG-oracle measurements. Swift tools 6.2 and macOS deployment minimum 26.0
remain in the consumer manifest; this run does not qualify Swift 6.2 itself.

[Consumer receipt](consumer/report.json) retains exact commands, exits, source
and binary hashes, toolchain and environment details.
[Source reconciliation](consumer/source-identity.json) records the clean fetched
checkout and the single changed shipping file. All 46 shipping files are
identified. This is revision-pinned consumption, not a stable tag, semver
resolution or DICOMKit integration.

**Both build-associated SBOM generation commands passed.** They ran against the
same clean fetched checkout, using release Swift Build with two jobs and
`--product SwiftJLI --sbom-spec spdx|cyclonedx --sbom-filter all`. Raw generated
documents identify the exact candidate and are retained unchanged.

Independent validation using the retained official schemas and isolated
`jsonschema 4.25.1` environment produced:

| Format | Result |
| --- | --- |
| CycloneDX 1.7 | JSON Schema passed; zero schema findings. |
| SPDX 3.0.1 | JSON Schema failed on two records containing `externalUrl` and `software_internalVersion`. |

The schema validator exited **1**, correctly preserving the SPDX failure.
The producer's missing schema bundle did not become a validation pass.
[SBOM receipt](sbom/report.json), [schema results](sbom/schema-results.json) and
[field audit](sbom/field-audit.json) retain generation, validation and separate
semantic/inventory findings. CycloneDX still repeats the root product `bom-ref`
and omits its licence field; neither format inventories the complete Apple
SDK/runtime. These producer limitations are not silently repaired or presented
as full SBOM conformance.

Reproduce with an immutable revision and new output directories:

```sh
python3 Documentation/Migration/Qualification/Milestone5/consumer-qualify.py \
  --revision f548e5048e5c71204c2a2ec4036bf66c4f040285 \
  --evidence /absolute/new/final-consumer-sbom
python3 Documentation/Migration/Qualification/Milestone5/sbom-prepare-schemas.py \
  --evidence /absolute/new/final-consumer-sbom/sbom
```

Use the resulting `validatorPython` from `sbom/schema-setup.json` to run the
retained `sbom-validate.py`; run `sbom-audit.py` separately. Both require a fresh
result file. [Helper identity and preservation checks](helper-review.json)
distinguish the original executed helper from the later explicit-revision
interface. The earlier consumer/SBOM receipts remain unchanged. No benchmarks,
full test-suite reruns or production changes were performed by these helpers.
