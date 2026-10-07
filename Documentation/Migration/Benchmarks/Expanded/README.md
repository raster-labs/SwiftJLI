# Expanded predecessor comparison

The retained `Comparison.swift` is a public-API executable depending on both pinned packages. Place the benchmark package beside JLISwift and SwiftJLI checkouts, install it as `Sources/Benchmark/main.swift`, and use the retained `Package.swift` (its local paths expect those sibling names).

The full run uses five warm-ups and twenty timed iterations per case at 512×512 and 1024×1024, alternating predecessor/successor order. It covers predictive UInt16, sequential DCT UInt12/RGB8, progressive RGB8 and XYB RGB8. Codestreams and decoded sample bytes must match before timing; lossless also checks the original source. Output includes raw samples, median, p95, extrema, throughput, compressed size, thermal/load context and paired-process peak RSS. The latter includes both implementations and earlier cases; it is not per-codec workspace or a peak-memory comparison. Separate allocator measurements remain necessary.

`preparation.json`, `build.log` and `smoke.jsonl` prove a clean release build and a **one-warm-up/one-measurement smoke** at 65×65. Smoke timings are not performance acceptance. Full timed runs have not yet been recorded here; they must run after competing fuzz/build work finishes.

The successful macOS build uses `-Xswiftc -gnone`. Default debug-symbol release linking repeatedly produced a runnable executable but did not terminate (the build sessions were interrupted with exit 130). A direct link with `-gnone` exited 0, and a fresh SwiftPM release build with that flag completed in 41.04 seconds, exit 0. This is a benchmark build workaround; shipping package settings are unchanged. Disabling sanitizers/tracing remains required for timings.

An attempted Linux build of the unmodified predecessor failed on its unconditional `CryptoKit` import. It is not a successor build failure, a successful Linux comparison, or permission to patch the pinned baseline. Current retained preparation targets macOS ARM64 / Apple Swift 6.4.
