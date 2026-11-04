# Prepared SBOM follow-up reproduction

This separate follow-up preserves the final replay performed after the original
prepared-revision archive was committed at `ec9843013adc7b0b6064312a1333354e601509b1`.
The original archive summaries and its 170-file manifest remain unchanged.

[Replay receipts](reproduction/receipt.json) retain exact commands, exits and
checks for both derived product SBOMs. Both validations pass and reproduce all
12 compared outputs byte-for-byte. No new codec build or runtime test ran.
This is further reproduction evidence, not stable-tag, DICOMKit or physical
qualification. The receipt retains its original capture paths under
`prepared-consumer-sbom/reproduction`; those captured files now reside here.

The late README/manifest are preserved as `late-README.md` and
`late-manifest.json` for provenance; they are not the authoritative summaries
of the earlier committed archive. The copied baseline manifest matches that
archive byte-for-byte.
