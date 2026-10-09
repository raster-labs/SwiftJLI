# Decode performance correction

The initial diagnostic compares the pinned predecessor with successor native, context and public paths at `ce3d8ae`. It uses five warm-ups and twenty timed samples in alternating order; all decoded sample buffers match. `decode-attribution-sources.json` records the shipping-source and binary hashes. `InitialAttribution.swift` reconstructs the initial harness by reversing only the added cases in the second experiment; no independent initial harness hash was recorded at execution. Its source is provided for reproducibility, not as a retrospectively captured hash.

At 1024², initial greyscale12 medians were 9.98 ms predecessor, 10.13 ms native with context and 12.84 ms public. Native parsing took 0.40 ms and validated parsing 0.83 ms. This separates the extra framing scan from the larger direct-output cost. Colour paths also paid for serial chroma interpolation under the operation context.

Changes:
- Both framing passes now use one checked entropy-boundary helper. Each `memchr` search spans at most 4096 bytes between cancellation/deadline checks; stuffed FF00, restart pairs, real markers and trailing FF retain their prior boundaries. Tests compare an independent bytewise reference, including search-window boundaries and empty/truncated inputs.
- Greyscale output has a specialised direct writer, retaining finite checks, clipping, ties-away rounding, explicit little-endian stores and untouched padding.
- Chroma interpolation uses the existing bounded joined-worker mechanism. The selected operation context and cancellation reach every worker, and row ranges are disjoint.
- RGB8 conversion uses scratch for at most eight rows, amortising vector-call overhead. Packed destinations receive one strided conversion per batch; padded destinations are written row by row. Source planes stay borrowed. This is algorithm scratch, not an intermediate packed image.

The second diagnostic (`decode-attribution-2.jsonl`) includes native and borrowed output from an already parsed stream, further isolating final output work. Diagnostic executables use release plus enable-testing to access internal controls; their absolute timings must not replace the public release comparison. Median stage times cannot simply be summed into exact causal attribution.

The latest ordinary public release run (`row-batch-benchmark.jsonl`) passes all output checks. Predictive decode is 9–15% faster and greyscale DCT decode 4–6% faster than the predecessor. RGB8 decode is 3–7% slower; progressive RGB8 decode remains 10–13% slower. Predictive encode remains 27–45% slower, and DCT encode 1–11% slower. These are single-run observations; repeated final acceptance remains open. The exact source and binary hashes are in `row-batch-sources.json`.

Linux Swift 6.4 passes 332 tests in 44 suites after these changes. The initial scanner/greyscale/chroma checkpoint passed local macOS ASan and TSan identity/public matrices and both 71-record predecessor comparisons, plus a three-second four-entry deterministic fuzz smoke. That smoke does not satisfy the final one-hour requirement, and it predates RGB row batching. The row-batch checkpoint's sanitizer results are recorded separately when complete.

CI 37731508684 failed on the preceding worker commit because a cancellation test assumed its Swift task would start within five seconds. On busy runners, the cooperative executor did not satisfy that assumption. The test now cancels from a dedicated thread only after actual worker entry and asserts both cancellation and a complete join; it does not impose a task-start latency requirement or depend on resuming a cooperative task to send cancellation. The kernel's checks were not weakened. Fresh CI remains required.

To reproduce attribution, put either InitialAttribution.swift or Attribution.swift (not both), plus Old.swift, in Sources/Attribution beside Package.swift and sibling pinned package checkouts. Build release with `-Xswiftc -gnone -Xswiftc -enable-testing --build-system native`, then run Attribution after other build/fuzz workers have finished. Normal public benchmarks use the retained Benchmarks/Expanded harness without enable-testing.

The final row-batch checkpoint also passed local macOS ASan and TSan identity/public matrices (both exit 0), with `cmp` against all 71 predecessor records exiting 0 in both builds. Logs are retained separately. These are executable-harness results, not a claim that the full CI Swift Testing sanitizer suite has run at this head.
