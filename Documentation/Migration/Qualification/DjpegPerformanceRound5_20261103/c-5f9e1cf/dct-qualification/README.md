# Local C entropy integration qualification

Pinned integration source: `281f3635e003dde60819be21254e982a22b30f3d`. Its `Sources` and `Package.swift` are identical to `e0cfea0fa2f702cb558f6896db03501efcd0b463`; the worktree remained clean. The integration includes the current portable worker-failure test correction.

| Gate | Result |
|---|---|
| Full Release |447 tests /76 suites, exit0|
| Focused Release + AddressSanitizer |62 tests /12 suites, exit0|
| Focused Release + ThreadSanitizer |62 tests /12 suites, exit0|

All passed on the first attempt. The C objects contain the corresponding ASan/TSan imports, recorded with hashes in [c-instrumentation.json](c-instrumentation.json). Exact commands, scratch paths, filters, log hashes and exit codes are in the per-gate command receipts. [qualification.json](qualification.json) records source equality, product hashes, scope and unexecuted gates.

The separate [standalone C diagnostic](../c-extension-safety/qualification.json) passed1,393,276 combined DC+AC cases at exact e0cfea0 and1,176,591 generic row cases at06eff27, using ASan+UBSan. The generic row is not part of this integration branch. Later row specialisations and SIMD work are not covered.

No new benchmark or CLI/oracle run took place in this qualification slot. Full-suite sanitizer and cross-platform gates were not run. These bounded safety results do not imply performance acceptance or all-input correctness. No shipping source changed during qualification.
