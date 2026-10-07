# Expanded predecessor comparison

The retained `Comparison.swift` is a public-API executable depending on both pinned packages. Place the benchmark package beside JLISwift and SwiftJLI checkouts, install it as `Sources/Benchmark/main.swift`, and use the retained `Package.swift` (its local paths expect those sibling names).

The full run uses five warm-ups and twenty timed iterations per case at 512×512 and 1024×1024, alternating predecessor/successor order. It covers predictive UInt16, sequential DCT UInt12/RGB8, progressive RGB8 and XYB RGB8. Codestreams and decoded sample bytes must match before timing; lossless also checks the original source. Output includes raw samples, median, p95, extrema, throughput, compressed size, thermal/load context and paired-process peak RSS. The latter includes both implementations and earlier cases; it is not per-codec workspace or a peak-memory comparison. Separate allocator measurements remain necessary.

`preparation.json`, `build.log` and `smoke.jsonl` prove a clean release build and a **one-warm-up/one-measurement smoke** at 65×65. Smoke timings are not performance acceptance. Subsequent full runs are retained below; the earlier smoke remains historical preparation evidence.

The successful macOS build uses `-Xswiftc -gnone`. Default debug-symbol release linking repeatedly produced a runnable executable but did not terminate (the build sessions were interrupted with exit 130). A direct link with `-gnone` exited 0, and a fresh SwiftPM release build with that flag completed in 41.04 seconds, exit 0. This is a benchmark build workaround; shipping package settings are unchanged. Disabling sanitizers/tracing remains required for timings.

An attempted Linux build of the unmodified predecessor failed on its unconditional `CryptoKit` import. It is not a successor build failure, a successful Linux comparison, or permission to patch the pinned baseline. Current retained preparation targets macOS ARM64 / Apple Swift 6.4.

## Full repeated measurement at 86c1d48

`qualified-results.json`, `run-1.jsonl` and `run-2.jsonl` retain two completed five-warm-up/twenty-iteration runs at both sizes, with exact shipping source and executable hashes. Both commands exited 0; all ten cases per run matched codestreams and decoded samples. The release build exited 0. No codec build or fuzz campaign ran locally during the measurements; thermal state stayed nominal (0). Ordinary host activity was not eliminated. This compares each public API's automatic behaviour, including its worker policy, rather than forcing equal worker counts.

Performance acceptance **fails**. Across the two repeats and sizes, median predictive encoding is 242–327% slower (3.42–4.27 times the predecessor duration); predictive decoding ranges from 0.8% faster to 4.5% slower. Median DCT encoding is 13–51% slower and DCT decoding is 9–38% slower. Raw timings and per-case percentages are retained rather than collapsed into a misleading aggregate throughput.

Source inspection identifies candidates for investigation, not measured attribution: the adapter forces native residual/entropy/trellis/reconstruction workers to serial execution while the predecessor parallelises; the cancellable DCT path creates and copies chunk arrays. Restoring concurrency must preserve the operation's worker ceiling, backend context, cancellation, storage leases and join-before-release requirements. Removing cancellation or re-enabling unbounded legacy Dispatch is not an acceptable performance fix.
