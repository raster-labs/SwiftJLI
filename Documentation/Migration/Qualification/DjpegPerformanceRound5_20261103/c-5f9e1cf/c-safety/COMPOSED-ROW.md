# Composed code-zero row safety extension

Exact production pin `5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd`. Source snapshots preserve all three C translation units and both headers. See [composed-row-qualification.json](composed-row-qualification.json) for counters and source identity, and `row-v4-composed-run1` for executed command/logs.

Version4 passed1,536,287 deterministic cases with ASan+UBSan, recovery disabled, exit0 and empty diagnostic stderr. It retains independent encoded sample/bit-ledger checks, adds first-code0 category1...7 models with short/long fallback symbols, compares each valid case to the composed generic row, and exercises permitted aliases. This is a safety diagnostic, not performance acceptance or an external JPEG oracle.

The failed version3 compile and exact sources are retained: a harness-only substitution produced `trial%DC_MODELS2`; no execution occurred. Version4 corrects that single token. Production source snapshots are identical across versions. The version4 `harness-extension.patch` intentionally preserves the earlier v2→v3 design delta; its final one-token correction is recorded in the version4 manifest and README. No failed receipt was overwritten.

Original generic06 and combinede0 version2 results remain separate and unchanged. The source snapshot READMEs describe their creation-time unexecuted state; command receipts establish subsequent execution. The corresponding Swift composed qualification passed fullRelease458/78 and focusedASan/TSan80/15 each.
