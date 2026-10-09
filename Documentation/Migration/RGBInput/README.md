# Borrowed RGB8 input conversion

Base: `bbb44675fd6f5997794ecf66aac349006fc636d4`; pinned predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Source, executable and harness hashes accompany the raw records. Timings use macOS ARM64 / Apple Swift 6.4; allocation qualification is a separate Linux/glibc experiment.

## Measured problem and implementation

The retained input-only experiment compares the predecessor RGB-to-YCbCr conversion against the borrowed successor path, with exact equality of all three Float planes after every call. With five warm-ups and twenty interleaved measurements, the original borrowed reader took 0.542 ms at 512² versus 0.164 ms for the predecessor; at 2048² it took 5.381 versus 4.457 ms. This is a stage diagnostic, built with `-enable-testing`, rather than whole-encoder acceptance.

The selected path deinterleaves ordinary RGB8 into bounded byte scratch, widens contiguous channels, and applies the existing coefficients and operation order into the required Y/Cb/Cr algorithm planes. Joined workers own disjoint row ranges and propagate the existing deadline/backend/cancellation context. vImage uses `kvImageDoNotTile`; source row padding is honoured. The source pointer remains inside its storage borrow, and no packed source frame is materialised. Scalar fallback remains available. RGBA, Float32, preconverted YCbCr, RGB-to-greyscale and UInt12 continue through their existing explicit-policy reader.

The three output planes are independent allocations, avoiding the previous shared zero-array copies. Each worker owns at most eight rows of three Float channels and, on Accelerate, three byte channels: at most `15 * width * min(8, laneRows)` bytes beyond the required output planes, excluding small allocation metadata. Scalar conversion scratch uses 12 bytes per batched pixel. Aggregate scratch is bounded by worker count and disjoint row ranges and is covered by the conservative DCT admission reservation. At width 2048 with eight full lanes the additional scratch bound is 1,966,080 bytes. This source-derived bound does not replace allocator measurement or complete workspace attribution.

The selected stage diagnostic measured 0.098 ms at 512² versus 0.150 ms for the predecessor, and 0.936 versus 4.463 ms at 2048², with identical planes. The improvement includes parallel colour arithmetic and bounded working sets; it is not attributed solely to the byte deinterleave call.

## Verification

Linux ARM64 Swift 6.4 passes **336 tests in 47 suites**, exit 0. `RGBInputBatchTests` covers widths 1/19/257, heights 1/7/8/9/17/257, scalar/available Accelerate, workers 1/8, guarded and padded source storage, exact native-plane equality and unchanged input bytes. The 257² case enters the parallel path. Focused macOS ASan and TSan probes execute the same matrix without the unavailable local Swift Testing macro runner; both build/run commands exit 0. Sources and logs are retained.

Two ordinary public release runs (ten cases each) and a targeted expanded RGB run (24 cases) completed with exit 0. Every compressed byte and decoded sample comparison passed, using five warm-ups and twenty timed measurements. Source and binary hashes were rechecked after completion. No local build, sanitizer, fuzz or allocation campaign overlapped these timing runs; recorded thermal state remained nominal. Ordinary host activity was not eliminated.

In the expanded run, large flat RGB encoding is 7–11% faster than the predecessor; large ramp RGB is 3–9% faster and large noise RGB is 1–4% faster. At 512², flat/ramp encoding still shows 6–15% overhead while noisy cases are 1–3% faster. Smaller-case variability and UInt12 DCT overhead remain unresolved; this is not a complete performance pass. `results.json` summarises each case, and the raw files retain absolute timings, spread, encoded size and process RSS. RSS is not separate workspace or copy accounting.

The attribution package requires sibling pinned JLISwift and SwiftJLI checkouts and a release build with `-Xswiftc -enable-testing -Xswiftc -gnone`. The sanitizer probe needs only SwiftJLI and runs with `swift run --sanitize address -Xswiftc -enable-testing Probe` and separately `--sanitize thread`. The public harness uses no testing flag or sanitizer.

Final fuzz, complete allocation/lifetime coverage, platform/runtime qualification and the remaining performance investigation are still open. No merge, stable release or consumer cutover is implied.

## Encoder heap experiment

`Scripts/run-allocation-probe.py --operation encode` completed **30 measurements and 30 deliberate full-source-copy controls** on Linux ARM64 / Swift 6.4, glibc, scalar kernels. Profiles are predictive16, DCT12, sequential/progressive RGB8 and XYB8 at 257²/1024², with three repetitions each. Every measured codestream matches its unmeasured reference. Calibration observes both C allocation entry points and Swift storage and derives a 32-byte array header; tracker overflow is forbidden. The measured normal paths contain no source-frame-sized allocation, and each deliberate copy adds exactly one. The codec's zero pixel-allocation report alone is not used as proof.

`EncoderAllocations` retains commands, source/executable/log hashes, requested-byte histograms, peak/live heap and controls. Inputs and warm-up allocations predate the measured scope. The interposer records malloc-family requested heap across threads, not allocator rounding, stack, mmap, RSS or a pure algorithm-workspace category. Matching size bins plus a positive control support the tested full-source-copy assertion; they do not detect every differently shaped or partial copy. Apple Accelerate allocation behaviour, failure/cancellation/concurrency accounting and full workspace attribution remain open. The decoder mode remains the default; its existing archived baseline/control records also pass the updated validator.

The current-source decoder experiment also passes **60 measurements and 60 deliberate-copy controls**, retained in `DecoderAllocations`. Allocating decode has one measured final-frame-size allocation; caller-destination decode has none and no measured packed intermediate frame. Each deliberate copy adds one expected allocation. All sample/padding/identity checks and tracker checks pass. This refreshes the earlier decoder measurement after the parallel RGB-output change, under the same Linux requested-heap limitations.
