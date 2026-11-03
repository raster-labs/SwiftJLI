# Independent Intel Watch evidence review

**Accepted for the recorded Watch simulator scope; no findings.** [The audit receipt](independent-audit.json) independently checks the terminal successful run at `8c1b9655319771d1fcaaa7f03c2d165ec3e7a333`, with shipping source bound to `f548e50`, tests/examples to `a44e671` and both helpers to `07cc31e`.

The retained raw logs and xcresult summaries agree: 389 Debug library tests in 60 suites, and six Release qualification tests in one suite, all with zero failures or skips. The library’s 617 parameterised device entries remain distinct from its 389 top-level declarations. All six unique Watch records retain the expected budgets and simulator environment. The actual environment is Intel/x86_64, macOS 26.6.1, Xcode 26.6, Swift 6.3.3 and watchOS 26.5 Simulator.

The audit verifies all 49 source identities against the tested Git tree and current bytes, the complete 1,401-file ZIP against its manifest and GitHub digest, 25 readable copies, and all 42 frozen capture files. All 51 original Watch result files are unchanged; only `database.sqlite3` was added to the 52-file query copy. The library’s original 1,273-file bundle and locally queried 1,274-file copy also verify, with only that cache addition. Receipt command/output hashes and the strict verifier’s parsed evidence checks pass.

One Watch job executed successfully; seven other job definitions intentionally skipped without runners or steps. This audit does not qualify those skipped jobs, physical hardware, system-RSS ceilings or performance. Existing failed attempts remain unchanged. No workflow action, codec build/test, benchmark, simulator or `xcresulttool` execution was performed for this independent review.
