# Predictive entropy stitching investigation

Predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Successor base: `fb86314257ef36414107b469fb64f089ad6f8d2f`, plus the exact shipping source hashes in `bulk-stitch-sources.json` and `expanded-sources.json`. The latter also pins the expanded harness and release executable. These are macOS ARM64 / Apple Swift 6.4 measurements; they do not establish other-platform performance.

## Finding and change

The eight-mode `encoder-overhead` experiment compared native, explicit context, cancellation token and public paths at worker ceilings 8/16. It did not explain the main predictive encoding gap. A separate copied-package control with operation checks disabled still had approximately 22–33% predictive encoding overhead. That control was diagnostic only: it was never a shipping implementation or a safety-qualified candidate. `check-control-sources.json` and its raw benchmark retain the distinction.

Instrumented copies then measured input reading, residual prediction/histograms, header/table construction, parallel entropy emission, serial stitching and final formatting. Median stitching times were 0.255 versus 0.393 ms at 512², and 0.939 versus 1.479 ms at 1024² (predecessor versus successor). The phase logs, source hashes, patches against the pins and harness are retained. These timings include instrumentation and are attribution evidence, not release acceptance results.

Moving checks outside the innermost loops or outlining the three-byte writer did not remove the regression. The selected implementation instead borrows the writer buffer once per bounded block of whole bytes, retaining the pending bit alignment and inserting `00` after every emitted `FF`. It grows capacity before the borrow and never retains the source pointer. Checks still occur before at most 12288 source bytes; residual entropy emission checks every 4096 samples. No cancellation/deadline check was removed. The speculative `@inline(never)` operation-check change was discarded.

## Validation

`BulkBitWriterTests` uses an independent bit-list, packing and stuffing oracle. It covers every pending-bit alignment, empty input, zero/FF/varying bytes, growth from a small capacity, lengths either side of batch boundaries, trailing bits and restart markers. The Linux ARM64 Swift 6.4 command `docker run --rm --ulimit core=0 -v "$PWD:/src" -w /src swift:6.4-noble swift test --scratch-path .build-linux -j 4` exited 0: **334 tests in 45 suites passed**. Raw output is retained. Provenance verification and `git diff --check` passed.

Two release public-API comparisons used five warm-ups and twenty interleaved measurements per case. All ten cases in each run matched predecessor compressed bytes and decoded sample bytes. Predictive encoding measured 7–8% faster at 512² and 3–5% faster at 1024². DCT encode/decode regressions remain; this does not pass the complete performance gate. These runs used automatic backends and each package's worker policy; they do not isolate equal worker counts.

The retained `Benchmarks/Expanded/Comparison.swift` now accepts `--extended`: 19², 512², 2048² and 3072²; flat, ramp and deterministic noisy patterns; predictive UInt16, DCT UInt12, sequential/progressive RGB8 and XYB8. It records all raw samples, output identity, encoded size, process peak RSS, thermal state and load. Explicit workspace/memory ceilings are 8/10 GiB to admit the conservative large-colour reservations; these ceilings are not measured allocations. This benchmark does not measure allocator/copy counts or separate process RSS by implementation. Those remain separate qualification work.

No codec build, sanitizer or fuzz worker was run concurrently with the timing runs. Ordinary host activity was not eliminated. The expanded corpus is a diagnostic coverage improvement and does not waive any >5% regression. Final sanitizer, fuzz, allocation and platform qualification remain necessary.

The expanded command completed with exit 0: **all 60 cases** matched compressed bytes and decoded samples, with five warm-ups and twenty measurements per case. Thermal state remained nominal (0). `results.json` summarises all 80 cases across the initial, repeat and expanded runs; raw files retain absolute timings and spread. Large flat RGB decode was 35% slower at 3072², and progressive RGB 42% slower. Very small images show larger relative fixed-overhead costs. These are unresolved regressions, not accepted safety trade-offs or release-ready results.

The selected shipping source also passed the local macOS AddressSanitizer identity/public executable (exit 0). Its 71 native identity records match the pinned predecessor file exactly (`cmp`, exit 0), and public storage/scale/Float32/XYB/ICC checks pass. `bulk-stitch-asan.log` and the identity output are retained. This is the executable harness, not the full Swift Testing sanitizer suite; CI qualification remains separate.
