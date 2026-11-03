# Original C AC leaf safety diagnostic

Source: `3a5ef320c04fff03561a69b705355c0e9da2fc31` (clean, unchanged).
This gate does not accept the candidate for performance or qualify later C-row/DC extensions.

- Focused Swift Release + AddressSanitizer: **42 tests / 10 suites**, exit 0. The C object is also ASan-instrumented.
- Standalone original C leaf, Apple Clang 21, `-O2 -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all`: compile and run exit 0, no diagnostics.
- **1,145,828 cases**: 1,048,576 deterministic random, 88,920 exhaustive small count/offset/available boundaries, 8,320 independently encoded exact-output cases, 12 no-write invalid-argument checks.
- Seed: `0x8ef16ab47c205d93`, xorshift64star. All initial available counts 0–64, categories 0–15, short/long canonical codes, FF stuffing, markers and truncation are covered.

See [qualification.json](qualification.json) for scope and limitations, [c-harness-results.json](c-harness-results.json) for every status/coverage counter, [clang-command.json](clang-command.json) and [swift-asan-command.json](swift-asan-command.json) for exact commands and exit codes. [ac_safety.c](ac_safety.c) is the original fixed-buffer diagnostic harness. Original C and header copies are retained with hashes for reproduction; commands name their pinned worktree paths.

No production sources changed. No fresh benchmark, full-suite, TSan or cross-platform result is claimed. The performance regression remains a separate acceptance blocker. The harness binary/dSYM and build objects are excluded from the text-only archive inventory.
