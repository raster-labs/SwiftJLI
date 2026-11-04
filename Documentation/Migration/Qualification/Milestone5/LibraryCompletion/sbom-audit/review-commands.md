# Completed read-only review commands

Working directory: `/Users/pushparaj/projects/SwiftJLI-release-completion`.
The tool session retained the full inline Python commands; this compact receipt
records their exact command families and operations, not an invented shell-history
capture. None of the commands below was executed again while writing this receipt.

- `git status --short` and scoped `rg --files` inventoried the two evidence directories.
- `cat` read both current READMEs, replay receipt, schema-reuse receipts and shared schema notices.
- Inline `python3 - <<'PY'` loaded the original 170-entry manifest and replay nine-entry archive manifest; each listed file was hashed with `hashlib.sha256` and compared. Actual file counts were 171 and 10 including the manifests.
- The same inline review called `git show ec9843013adc7b0b6064312a1333354e601509b1:<repository-relative-file>` for every original archive file and compared exact bytes. The baseline-manifest copy was compared byte-for-byte.
- Inline Python compared the replay receipt's six hashes per product with both retained original outputs and `/private/tmp/swiftjli-prepared-sbom-reproduction-2e8hb2c9/{library,cli}`. It checked recorded exits and stdout/stderr/helper hashes, then read JSON Schema and SHACL reports. It did not execute either validator or the derivative helper.
- `rg -n 'validate\(|allow_warnings|allow_infos|conforms|schema|socket|source_revision|rawHashes|shacl|fetch|download' .../helpers/derive-prepared.py` and `sed -n '240,310p' .../helpers/derive-prepared.py` inspected actual schema/model loading, local-only retrieval, semantic checks, warnings/info policy and success conditions.
- Inline Python resolved local Markdown links from prepared README, replay README and schema-licences README; checked all eight schema copies against compressed/uncompressed hashes and retained historical bytes; checked all 44 captured inputs against their hashes and sizes; checked both products' raw output hashes and official model binding.
- Inline Python checked stdout/stderr hashes and exits in product-qualification.json, consumer/report.json, sbom/report.json and cli-raw/report.json. The report lists overlap and were not summed as distinct commands.
- Inline Python called `git show 7739dba554cabebcc25e3593af3feb6ba27f8489:<shipping-path>` for 46 shipping Swift files and `Package.swift`, compared SHA-256 to the consumer receipt, and read the genuine remote URL and single resolved revision.
- `nl -ba .../prepared-consumer-sbom-replay/README.md` checked the explicit distinction between archived late captures and authoritative summaries; final `git status --short` showed no review edits.

No build, test, benchmark, network request, validator run or evidence mutation
was performed by this audit. The receipt itself was subsequently written only
to a fresh directory under `/private/tmp`.
