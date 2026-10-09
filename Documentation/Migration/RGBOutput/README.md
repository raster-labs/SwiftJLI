# Direct RGB output qualification

Base revision: `535938a989ba3e8f0a3a33aa560353b1c94662f1`; predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Shipping source, public release executable and harness hashes are in `public-sources.json`. Measurements use macOS ARM64 / Apple Swift 6.4. Other platforms are not inferred from these timings.

## Attribution

The prior expanded corpus exposed a 35–42% decode regression on large flat RGB images. The retained flat-colour diagnostic compares parsing, native output, direct borrowed output, public decoding and worker ceilings of 8/16. It checks decoded bytes against the actual pinned predecessor after each timed operation. Five warm-ups and twenty interleaved measurements per mode are retained.

At 2048², the initial sequential RGB public median was 16.04 ms versus 11.89 ms for the predecessor; progressive RGB was 14.06 versus 10.05 ms. The same native kernel with its old output writer was close to the predecessor. Validated parsing took only 0.014–0.016 ms, and selecting 16 workers did not remove the gap. This isolates final shared-storage colour output rather than parser validation or worker ceilings.

The predecessor already converts floats into contiguous byte planes and uses vImage to interleave them. The borrowed writer instead used three stride-three vDSP stores. Restoring contiguous byte conversion in bounded scratch reduced the gap substantially. Dividing the remaining output work among bounded joined lanes then measured 8.91/7.37 ms for sequential/progressive public decoding at 2048², versus 11.59/10.00 ms for the predecessor in that diagnostic run. These instrumentation-free but `-enable-testing` diagnostic comparisons explain the change; the normal public release harness supplies acceptance evidence separately.

The successive raw files and source hashes distinguish the original writer, single-lane contiguous conversion and selected parallel writer. The parallel diagnostic hashes were reconstructed after a documentation-comment edit; that fact is recorded explicitly. No executable-code change is hidden in that reconstruction.

## Implementation and memory

Sources remain borrowed read-only. Each lane owns conversion scratch and a disjoint range of final destination rows; `NativeOperation.perform` propagates context, bounds lanes and joins before the destination lease or source borrows end. It checks cancellation/deadlines between batches. vImage uses `kvImageDoNotTile`, preventing that interleave call from adding framework-managed parallel work.

Each lane uses at most eight rows of five Float planes plus three byte planes on Accelerate: at most `23 * width * min(8, laneRows)` bytes, excluding small array metadata. Scalar output needs only the five Float planes. Total conversion scratch is bounded by both the active lane count and the partitioned image rows, and fits within the existing conservative DCT reservation. At width 2048 and eight full lanes this bound is 3,014,656 bytes. This is algorithm conversion workspace, not an extra hand-off image; there is no packed frame intermediate. It is a source-derived bound, not an allocator measurement or a claim that peak workspace reporting is complete.

Accelerated conversion retains clipping and nearest-even integer conversion, then interleaves into the caller's actual row stride. The scalar path remains available. Padded Y planes use one row per batch. Byte-plane interleave failures return an internal error; no partially written destination is published.

## Validation

- Linux ARM64 Swift 6.4: **335 tests in 46 suites passed**, command exit 0. `parallel-rgb-tests.log` retains the full output.
- `RGBOutputBatchTests` compares the selected output against the retained native conversion for fractional samples and clipping, widths 1/19/257, heights 1/7/8/9/17/257, worker limits 1/8, scalar and available Accelerate backends, padded source rows and both packed/padded guarded destinations. The 257² case actually enters parallel output; batch boundaries and prefix/suffix/padding preservation are checked.
- Local macOS AddressSanitizer and ThreadSanitizer probes execute that same matrix without the unavailable local Swift Testing macro runner. Both build/run commands exit 0. Probe source and raw logs are retained. This is a focused memory/race check, not a substitute for the full CI suite.

The probe is reproducible as a standalone package beside SwiftJLI with `swift run --sanitize address -Xswiftc -enable-testing Probe` (and separately `--sanitize thread`). The attribution package also needs the pinned JLISwift sibling and a release build with `-Xswiftc -enable-testing -Xswiftc -gnone`. The public benchmark uses no testing flag, sanitizer or tracing.

Final-head fuzz, independent allocation accounting, broader platform/runtime qualification and unresolved encoder performance remain separate gates. No release, merge or consumer cutover is implied.

## Public release results

Two ordinary runs (ten cases each) and the targeted `--extended --rgb-only` run (24 cases) completed with exit 0. Every case matched compressed bytes and decoded samples, using five warm-ups and twenty timed measurements. The binary hash and shipping source hashes were rechecked after completion. No local codec build, sanitizer or fuzz campaign overlapped these runs.

Flat RGB and progressive RGB at 3072² now decode 22–23% faster than the predecessor; the 2048² improvements are 25–28%. Mixed 1024² RGB decoding ranges from 0.2–3.4% faster across the two repeats. The 512² runs are more variable: the second mixed run is 10–13% slower while the first is close to parity, and the expanded flat/progressive-noise cases retain 5–10% overhead. Small 19² cases also retain substantial relative fixed overhead. Encoder regressions remain (the writer does not change encoding). Raw samples, absolute medians/spread and per-case percentage summaries are retained; no broad performance pass is claimed. Additional controlled investigation is required before release acceptance.

The four public parser/decode entries also passed a three-second deterministic mutation smoke at the selected source (supervisor exit 0). `FuzzSmoke` retains the manifest, source/binary hashes and raw logs: common inspection 515610 attempts, JPEG inspection 520653, allocating decode 67356 and caller-destination decode 61803. This short Linux scalar smoke is not final one-hour qualification or an accelerated-path race test.
