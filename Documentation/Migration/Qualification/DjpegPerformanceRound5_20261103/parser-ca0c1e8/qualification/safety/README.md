# Parser-only safety continuation

Source ca0c1e874177f429ed199f3ed8ef6ac1315ee66a remains unchanged. Earlier full Release, paired native and default-admission results are preserved in the parent directory. Optional FMA composition2717e42 is held unbuilt because its ba277 parent regressed; it is not this candidate.

`run.py` prepares focused Release-mode ASan and TSan tests plus the unchanged252-check CLI regression. All source/test/CLI inputs and the existing Release executable are pinned in `source.json`. Separate scratch paths and fresh evidence directories avoid overwriting any prior attempt. CPU grant is required before adding `--execute`.

```
python3 /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/run.py --gate asan --output /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/asan-1
python3 /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/run.py --gate tsan --output /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/tsan-1
python3 /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/run.py --gate cli --output /private/tmp/swiftjli-round5-evidence/parser-reservation/safety/cli-1
```

Commands without `--execute` print the plan. The sanitizer filter covers parser reservation/envelope/admission, retained-owner COW, general ownership and NativeExecution, parity/metadata/boundaries, and public C-row/pipeline provider paths. It is a focused gate, not the entire suite under sanitizers. CLI checks use the already-built Release executable and clean source checkout, including its matching manual and installer; no further build is needed for that gate. No gate has executed at preparation time.

## Executed continuation

All three requested gates passed on the first attempt with the source and all182 pinned file hashes unchanged:

| Gate | Result |
| --- | --- |
| Focused Release ASan | 71 tests / 11 suites; exit0 |
| Focused Release TSan | 71 tests / 11 suites; exit0 |
| Unchanged CLI regression, Release executable | 252 process checks; exit0 |

`qualification.json` links the exact command receipts and initial qualification hash. `c-instrumentation.json` records sanitizer runtime imports in all three C translation units for each build (11/11/13 imports). The CLI executable retains SHA256 `39a684f56965f0a6c86bd37c2189ae7376b915672973476780a17abf345a97eb`. No production edit, joint-candidate build, benchmark or RSS measurement occurred in this continuation. These are local focused sanitizer gates and Release CLI tests, not full-suite sanitizer or cross-platform CI qualification. The parent owns integration and the separate newly eligible CLI timing report.
