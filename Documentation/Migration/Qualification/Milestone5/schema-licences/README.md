# Third-party schema and model notices

This notice covers the retained qualification schemas in
`../sbom/schemas/` and `../final-consumer-sbom/sbom/schemas/`, and the SPDX
model/context used by `../final-consumer-sbom/derived/`. These materials remain
under their upstream terms. The repository's Apache-2.0 licence does not
relicense them. No schema or model bytes were modified; gzip is lossless.

[receipt.json](receipt.json) identifies all 12 retained compressed copies,
their uncompressed/compressed SHA-256 values, and the downloaded licence texts.
The separately retained first download attempt contains the same unmodified
CycloneDX and SPDX licence files and records its interrupted final retrieval.

| Material | Upstream source and attribution | Retained terms |
| --- | --- | --- |
| CycloneDX 1.7 JSON Schema and `spdx.schema.json` | OWASP Foundation, CycloneDX specification commit `1ce97b2a7b8cf2429da248560d2aa671c6bce74a`. The BOM schema's Apache-2.0 statement remains embedded. | [Exact upstream LICENSE](CycloneDX-LICENSE), including its OWASP Foundation copyright. No separate upstream root NOTICE was found at that pin. |
| JSON Signature Format `jsf-0.82.schema.json` | Same CycloneDX commit. The schema retains its Apache-2.0 statement and attribution to Anders Rundgren and the OpenKeyStore project. | [Apache-2.0 text](CycloneDX-LICENSE); the original JSF-specific attribution remains inside each compressed schema. |
| SPDX 3.0.1 JSON Schema | SPDX Project / SPDX Working Group; canonical publication `https://spdx.org/schema/3.0.1/spdx-json-schema.json`, SHA-256 `582c64e809d5b3ef9bd0c4de13a32391b47b0284a3e8d199569fb96f649234b1`. Its `shacl2code` generator comment is unchanged. | [SPDX specification licence record](SPDX-SPEC-LICENSE): Community Specification License 1.0, with pre-existing CC-BY-3.0 portions as explained by upstream. This is not represented as Apache-2.0 or as a grant from SwiftJLI. |
| SPDX 3.0.1 OWL/SHACL model and JSON-LD context | SPDX Project, canonical versioned publications under `https://spdx.org/rdf/3.0.1/`. The model itself declares Community-Spec-1.0 and Copyright (C) 2024 SPDX Project. Exact publication hashes are in the derived input receipt. | [Model licence](SPDX-MODEL-LICENSE.md) from peeled 3.0.1 tag `a745f63e8643d5ae0f0851fcfa6836085308f80b`. Its licence text retains the Joint Development Foundation copyright and CC-BY-4.0 notice for that text. |
| Swift package URL type definition | The purl authors; exact source commit and URL are recorded in `../final-consumer-sbom/derived/inputs/receipt.json`. | [Exact upstream MIT licence and copyright](PURL-SPEC-LICENSE). |

The inspected SPDX specification repository licence is pinned to
`61a7a341f2533d6e084c48c88463da63f05e1af0`. Its restored 3.0.1 schema has different
bytes from the canonical published schema retained here. That repository commit
therefore identifies the **licence evidence only**, not an exact source build of
the retained schema. The schema's accurate provenance is its canonical SPDX
publication URL, version and content hash; an exact generating source commit is
not established. SPDX's [3.0.1 serialization specification](https://spdx.github.io/spdx-spec/v3.0.1/serializations/)
identifies that canonical schema and model as the structural and semantic
validation inputs.

The Community Specification licence's provisions for source code are retained
without assuming that every generated specification artefact has been separately
relicensed as source code. No private material or runtime codec dependency is
introduced by retaining these development-only validation inputs.

Reproduce the licence capture using the pinned URLs in
[capture-licences.py](../final-consumer-sbom/derived/capture-licences.py) and a new
output directory. Exact original schema downloads and hashes remain in each
original `schema-setup.json`; those historical receipts are unchanged.
