# Standalone C sanitizer extensions — source only

These harnesses have been implemented but **not compiled or executed**. No result is claimed. The copied codec files are immutable snapshots:

- `combined/`: `9f11312eb43e1501f81fe6c4845934114099151c`.
- `row/`: `06eff275d4a2b72b3497748064311a38b288aa7d`.

`combined_safety.c` checks DC/AC publication stages, malformed categories, inclusive precision bounds, predictor extremes, logical bit consumption, buffered suffixes, raw input representations, output guards and no-write invalid arguments. `row_safety.c` checks every lossless category, modulo samples, first/last/written results, row lengths through65535, truncation/partial rows, raw UInt32-backed output, and10000 permitted alias comparisons against repeated single-sample calls. Both add1048576 bounded deterministic random cases and88920 exhaustive small count/offset/available cases. Known generated streams use the canonical encoder and byte/bit ledger in `safety_support.h`; no second entropy decoder is used as an oracle.

The row invocation is isolated in `row_call` for a separately pinned later short-table extension. This version does not include or qualify that later source. Combined buffers remain disjoint; only the row's input/output may overlap. Alias checks poison outside their live-range union and verify unchanged bytes outside the returned written prefix.

Exact seeds, planned compiler flags and scope are retained in the parent `planned-config.json`. `source-manifest.json` hashes every source, copied codec/header, driver and this README. The Python driver verifies those hashes and refuses to overwrite an existing receipt directory.

After an explicit CPU grant, use (one target at a time):

```sh
python3 run_safety.py --target combined --receipt-dir /private/tmp/swiftjli-round5-evidence/c-extension-safety/combined-v1-run1 --execute
python3 run_safety.py --target row --receipt-dir /private/tmp/swiftjli-round5-evidence/c-extension-safety/row-v1-run1 --execute
```

Omit `--execute` to print the compile plan without building. Clang flags are `-O2 -g -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all`; no flags or harness code enter the shipping package. The driver retains compile/stdout/stderr logs, compiler version, commands, source manifest/binary hashes, exit status and count validation. It preserves failed attempts separately. A successful diagnostic would not establish performance acceptance, cross-platform qualification, external-oracle parity or later-source safety.
