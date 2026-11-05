# Standalone C entropy safety qualification

Both version2 harnesses compiled and passed on their first attempt with AddressSanitizer and UndefinedBehaviorSanitizer, warnings-as-errors, and no diagnostics.

| Pinned leaf | Total cases | Random | Small boundaries | Known/encoded | Permitted aliases | Invalid arguments |
|---|---:|---:|---:|---:|---:|---:|
| Combined DC+AC `e0cfea0` | 1,393,276 | 1,048,576 | 88,920 | 255,761 | 0 | 19 |
| Generic lossless row `06eff27` | 1,176,591 | 1,048,576 | 88,920 | 29,078 | 10,000 | 17 |

[qualification.json](qualification.json) records full source pins, commands, counters and limits. [combined results](combined-v2-run1/results.json) and [row results](row-v2-run1/results.json) retain every status/coverage counter. Their command receipts contain compiler flags, source-manifest and binary hashes, exit codes and elapsed durations. [Version2 source](v2-source/README.md) is retained unchanged; its source-only wording records the pre-execution state. Version1/9f11312 remains unexecuted and preserved separately.

The tests cover all available-bit counts0–64, canonical short/long codes, DC and AC magnitude boundaries, malformed categories, precision limits, exact partial publication, logical bit consumption, raw typed storage, poisoned tails and output guards. The row alias comparisons use the explicitly permitted overlap contract and verify unchanged bytes outside the written prefix.

These are bounded memory/undefined-behaviour diagnostics, not performance acceptance, external-oracle parity or platform qualification. The integrated Swift Release/ASan/TSan checks have a separate source-pinned receipt. Later short-table/code-zero row source is not covered. No shipping sources changed.
