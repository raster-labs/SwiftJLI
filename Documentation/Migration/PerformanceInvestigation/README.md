# Performance investigation

The full public release benchmark at `86c1d48` failed acceptance. This directory retains intermediate diagnostic evidence; these measurements do not waive that gate.

## Predictive attribution before optimisation

The `Attribution.swift`/`Old.swift` executable compares the actual pinned predecessor with the successor native and public paths. The successor source hashes match `35aff33` (shipping source unchanged from `86c1d48`). Place the source files in `Sources/Attribution` beside the retained Package.swift, with sibling JLISwift/SwiftJLI checkouts. Build release with `-Xswiftc -enable-testing -Xswiftc -gnone --build-system native`; the test-only access sets existing serial/parallel test gates without modifying either codec source. Raw records use five warm-ups and twenty timed samples in alternating order and verify every codestream.

Median milliseconds:

| Size | Predecessor parallel | Predecessor serial | Successor native parallel | Successor native serial | Native operation context | Public successor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 512² | 0.536 | 1.542 | 0.556 | 1.648 | 1.754 | 1.920 |
| 1024² | 1.636 | 6.250 | 1.759 | 6.756 | 7.065 | 7.692 |

Forcing the predecessor serial accounts for most of the observed predictive slowdown. Operation context and public adaptation add further cost. This uses a different deterministic sample pattern and an enable-testing build; it diagnoses the cause and does not replace the public release benchmark. The attempted macOS `sample` profiler could not examine the process (exit 255), so no call-stack profile is claimed.

## Bounded workers and buffer ranges

The implementation now propagates operation context and a mutex-protected cancellation token into joined Dispatch lanes. The lane count respects both the caller worker limit and available CPUs. Every worker completes before a scoped storage borrow can return, including error and cancellation. Predictive residual/entropy stages, DCT trellis/AC histograms and full-resolution reconstruction use this mechanism. Checks remain between bounded sample/block units; progress callbacks remain on the invoking task. Predictive segmented decode and chroma upsampling retain their existing serial public policy.

Unsigned samples using their entire storage width no longer need an impossible out-of-range preflight scan. Reduced precision still receives the bounds check. Forward DCT and quantisation use scoped buffer ranges to avoid per-chunk input/output array copies; algorithm transform rearrangement and necessary workspace remain.

`parallel-benchmark.jsonl` records the predictive-worker change; `parallel-dct-benchmark.jsonl` adds DCT workers and less granular predictive cancellation checks. Their accompanying source/binary hash manifests identify the then-uncommitted source exactly. Each release benchmark command exited 0 and output checks passed. The first reduced predictive encode overhead to 38–50%, and the second to 31–42%. DCT encode overhead in the second is 6–16%, while decode remains 3–31% slower, depending on profile/size. These are intermediate single full runs; final repeated performance acceptance remains open.

Linux Swift 6.4 passes 328 tests in 43 suites, including new worker-cap/backend propagation, join-on-failure, in-flight cancellation, deadline and public serial/parallel exact-output tests. The cancellation test suspends the Swift task while a dedicated thread waits for work to start; it does not assume Dispatch starts every lane simultaneously. Mac sanitizers and current-head CI remain required.

The final buffer-range checkpoint (`borrowed-batch-benchmark.jsonl`, exact sources/binary in `borrowed-batch-sources.json`) completed one full release run with output checks and exit 0. DCT encoding is now 2–7% slower and XYB decoding 3–5% slower; other DCT decode remains 19–31% slower and predictive encode 34–38% slower in this run. These are still unresolved regressions, not repeated final acceptance. Linux's full 328-test suite passed after the buffer refactor. The macOS identity executable passed, and `cmp` against the executed predecessor exited 0 for all 71 native records; public float/XYB/borrowed-storage checks in that executable passed too.
