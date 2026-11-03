# Lossless left-predictor UInt16 specialisation diagnostic

Source: `723d5a9a90a7f9a0c56670405987ca200cbbcc01` on `codex/djpeg-round5-lossless-specialisation`, based on `0d56e447664b09ece1bcb0213c34e8b6c9922e31`. Round-four baseline: `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8`. Suite policy 0.10.0; unchanged Swift6.2 manifest minimum, Swift6.4 primary, Apple OS26 floor.

The new helper applies only to the large scalar fallback after zero-run, combined-lookup and tiny-image selection: predictor1, point transform0, UInt16 output. It saves one previous-row-first sample instead of allocating row history, keeps identical per-row cancellation/restart checks, and uses modulo65536 arithmetic followed by an unaligned little-endian raw word store. Destination arithmetic remains checked; no pointer escapes the synchronous borrow. Public output, quality and resource limits are unchanged. The existing admission is conservative because row history is removed.

## Safety and emitted code

The preceding8ddb42b raw store is sound: current supported storeBytes has no alignment requirement, the old clamp and little-endian bytes are preserved, and every sample lies within the checked destination payload. Tests cover odd base/stride and padding. Linked0d56 code contains strh in both UInt16 loops (326 disassembly lines versus365 for3c69), with no reintroduced general shift or memcpy. Lossless difference helpers are instruction-identical between3c69 and0d56. This proves store fusion, not the cause of the measured regression.

The specialised inner loop is retained in specialised-linked.txt: one difference call, modulo reduction, postincrement strh, without output shift/clamp, bytes-per-sample branch or history allocation. The zero-run decoder and consumeZeroDifferences instructions are unchanged from0d56 after normalising addresses.

## Executed tests

`swift test -c release --jobs 4 --scratch-path /private/tmp/swiftjli-round5-lossless-build --filter "LosslessLeftUInt16Tests|LosslessRowStorageTests|LosslessLookaheadTests|ZeroRunLosslessTests|LosslessRestartTests|LosslessDifferenceTests"` exited0:22 tests in6 suites. New tests construct two-category SOF3 scans that explicitly exclude zero-run and combined lookup, and compare every sample with the full-plane decoder. Coverage includes width1, single row, minimum large-path count, odd base/stride and padding, widened2/8-bit and12/16-bit samples, category16 wrap, row-aligned restarts, undersized/overflowing layout, cancellation and missing/truncated restarts. No ASan, TSan, Linux or CI result is claimed for this isolated patch.

## Three-way timing

run-native.py exited0. All16 cases in all6 processes passed full-output equality before timing. Same original public allocating-output harness,5 warmups and20 individual samples, order round4→0d56→specialised then reverse. Raw samples, compiler/object/executable/source hashes, commands and process snapshots are retained in native.json and adjacent files. Negative percentages below mean faster.

| Case | Change versus round4, rounds1/2 | Change versus0d56, rounds1/2 |
|---|---:|---:|
| flat-19 | +61.55%/-18.71% | +107.05%/+15.92% |
| flat-512 | +93.74%/-5.10% | +94.60%/-1.93% |
| flat-2048 | +33.91%/-3.78% | +31.38%/+3.77% |
| flat-3072 | +6.00%/-2.84% | +4.53%/-1.10% |
| ramp-2048 | +2.02%/-0.02% | -7.46%/-8.25% |
| ramp-3072 | +0.10%/-8.26% | -6.77%/-14.16% |
| noise-2048 | -0.79%/+0.29% | -1.13%/-1.28% |
| noise-3072 | -1.09%/+0.11% | -1.92%/-0.01% |
| mixed-2048 | -1.16%/-1.80% | -0.16%/+0.17% |
| mixed-3072 | -1.02%/-2.01% | -0.23%/+0.00% |

## Required focused repeat

The initial specialised process had large flat-only first-round outliers. run-focused.py therefore links the same three pinned objects with a flat512/2048/3072 subset of the original harness and an unchanged tiny19 harness using500 decodes per sample (allocation, decode and release included),5 warmup samples and20 measured samples. All12 processes exited0 and all outputs matched exactly. The focused result does not replace or discard the first matrix.

| Case | Change versus round4, rounds1/2 | Change versus0d56, rounds1/2 |
|---|---:|---:|
| flat: flat-512 | +5.83%/+0.96% | +11.03%/+5.56% |
| flat: flat-2048 | +11.34%/-19.05% | +12.50%/-12.64% |
| flat: flat-3072 | +16.86%/-4.15% | +15.39%/-5.62% |
| tiny: flat-19 | -15.96%/-24.21% | +22.75%/-11.26% |
| tiny: ramp-19 | -3.51%/-27.33% | +19.48%/-8.69% |
| tiny: noise-19 | -34.64%/-23.46% | +2.51%/+11.09% |
| tiny: mixed-19 | -26.14%/-5.53% | +0.14%/-2.43% |

Interpretation: the repeated large ramp regression is recovered, and tiny batches remain faster than round4. Broad no-regression acceptance is not established: focused flat512 is slower than0d56 by11.03%/5.56%, with other large and tiny fluctuations changing sign. These paths do not select the new helper, and zero-run code is instruction-identical, but that is not proof that host noise is the sole cause. All timings remain provisional because unrelated live workloads were present; snapshots show WindowServer and intermittent WebKit/VM activity. Do not count these as accepted CLI/djpeg wins. Parent integration needs its normal release, oracle, lifetime/race and final performance qualification.
