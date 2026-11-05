# Composed C-row qualification

Source `5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd`, compared with qualified `281f3635e003dde60819be21254e982a22b30f3d`. The worktree remained clean and all recorded source hashes match after execution. `NativeExecution.swift` and `ACBlock.c` are byte-for-byte identical to that baseline.

All Swift runs exited0: full Release458 tests/78 suites; focused ASan80 tests/15 suites; focused TSan80 tests/15 suites. The focused filter includes the row native/public suites, typed/odd output, actual partial-write abort, cancellation, restart, C differentials, pipeline ownership and compressed-input lifetime. Every C translation unit has sanitizer imports in the corresponding build; exact object hashes/imports are retained in `c-instrumentation.json`.

The exact composed code-zero entry also passed1,536,287 standalone ASan+UBSan cases:1,048,576 random,276,423 boundaries,201,266 independently encoded/known cases,10,000 aliases and22 invalid arguments. Seed `0xc0d0187a9b56e243`. Models cover first-code0 categories1...7 and6/9/16-bit fallback codes, all available bit counts0...64, every short prefix/offset, malformed/truncated data, maximum-width rows and modulo65536 samples. Every valid case has a composed generic-row differential; encoded cases also have independent expected samples and a bit ledger. The primary corpus is memory/error-sequencing evidence, not a benchmark.

The first standalone source version3 failed compilation because a harness model-count substitution changed `trial%32` into the undeclared `trial%DC_MODELS2`. It never ran. The complete failed snapshot and receipt remain retained. Version4 fixes only that harness token; production sources are unchanged. Version4 compilation and execution both exited0; compile and sanitizer stderr logs are empty. Earlier generic06 safety results remain separate.

Exact commands, logs, source hashes and exclusions are in `qualification.json` and the manifest. No new timing/RSS, CLI/oracle, remote CI, full-suite sanitizer or block-local IDCT/FMA integration gate ran in this slot. These local passes do not establish overall optimisation completion.
