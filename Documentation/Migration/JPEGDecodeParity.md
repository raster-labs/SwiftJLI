# JPEG decode parity — 12 October 2026

SwiftJLI baseline `a967d27bc5756fab8b7fe9db6eb302ff0645c362`; common contract 0.10.0. Sources: JLISwift `fix/bounded-dicom-decoding` at `a250354a2feec396aad533d8b6999b88cc1160ef` and `fix/jpeg-chroma-sample-centers` / v0.5.2 at `981da4efb7d62e4370c5d6de706d56a729b9552e`.

## Behaviour and scope

- Centred reconstruction and component rounding are applied once, before either final-storage writer, for full-resolution integer subsampled YCbCr. The helper is adapted from JLISwift with bounded cancellation and joined disjoint-row workers. Unlike a blanket predecessor cherry-pick, 4:4:4 retains its established reconstruction: rounding that path broke the existing tighter natural-texture oracle. No oracle threshold was relaxed. Preview, greyscale, floating-point and XYB paths retain their behaviour.
- Raw RGB DCT is recognised through Adobe transform 0 or RGB component IDs. Optional `DecoderConfiguration(sourceColourModel:)` handles unmarked three-component input consistently in both inspection methods and decode. Raw RGB supports 8/12-bit integer output and scales 1/2/4/8, with direct writes into caller storage. Unknown ICC profiles, conflicting markers and unsupported overrides are refused; no general colour management was added.
- Exactly one zero byte may follow an odd-length complete JPEG. Extra padding, a pad on an even-length JPEG, garbage, concatenation, missing EOI and invalid resource budgets are still refused. Resource defaults, encoders, platform minima, package dependencies and release version are unchanged.

## Executed verification

| Gate | Outcome |
| --- | --- |
| Before implementation, new parity suite on Linux Swift 6.4 | Failed as expected: 3 test declarations, 27 issues (24 chroma threshold failures, two raw RGB refusals and padding refusal) |
| Final complete Linux suite | 349 tests in 50 suites passed; exit 0 |
| Final Linux AddressSanitizer selection | 15 tests in 3 suites passed; exit 0; `ASAN_OPTIONS=detect_leaks=0`, so this is not a leak qualification |
| Original macOS verification probe, final Release library | All 15 independent chroma fixtures pass on scalar and automatic execution (30 decodes); maxima 0–2 with unchanged limit 3. All 15 other probes have the required acceptance/rejection. Exit 0. |
| Raw RGB permanent tests | Analytical 8/12-bit values, both backends, all four scales, allocating and padded caller-storage output; RGB identifiers, explicit RGB/YCbCr override and conflicting metadata |
| Ownership and concurrency | Same caller allocation, zero hand-off pixel allocations/copy events, prefix/row padding preserved; centred upsampling agrees exactly with one and four workers |
| macOS Debug and Release builds | Passed |
| macOS identity matrix | All 71 encoder hashes unchanged; 64 decoded records unchanged. Seven corrected decoded records exactly match an independent run against JLISwift v0.5.2. |
| macOS ThreadSanitizer standalone harness | Passed, exit 0: four concurrent 257×257 decodes with four workers each match a one-worker control; no race diagnostics |
| Linux ThreadSanitizer | Runner could not start due to incompatible ASLR memory layout; no race result from that environment |

The command forms below use this chat's workspace as the working directory. Build artefacts stay outside the repository.

```sh
docker run --rm --network none -v "$PWD/work/SwiftJLI:/src:ro" -v "$PWD/work/linux-build:/build" swift:6.4-noble swift test --package-path /src --scratch-path /build -j 4
docker run --rm --network none -e ASAN_OPTIONS=detect_leaks=0 -v "$PWD/work/SwiftJLI:/src:ro" -v "$PWD/work/linux-asan:/build" swift:6.4-noble swift test --package-path /src --scratch-path /build -j 4 --sanitize address --filter 'JPEGDecodeParityTests|CancellationPublicationTests|RGBOutputBatchTests|NativeExecutionTests'
docker run --rm --network none -v "$PWD/work/SwiftJLI:/src:ro" -v "$PWD/work/linux-tsan:/build" swift:6.4-noble swift test --package-path /src --scratch-path /build -j 4 --sanitize thread --filter JPEGDecodeParityTests
swift build --package-path work/SwiftJLI --scratch-path work/candidate-release -c release -Xswiftc -enable-testing
swift build --package-path work/SwiftJLI --scratch-path work/mac-tsan --sanitize thread
swiftc -parse-as-library -sanitize=thread -I work/mac-tsan/out/Products/Debug -L work/mac-tsan/out/Products/Debug -lSwiftJLI work/race-probe.swift -o work/mac-race-probe
work/mac-race-probe work/stress.jpg
```

The standalone probe and synthetic stress-image generator sources are retained beside the measurements. The final library-source hashes in the evidence also match the sanitizer build.

Local macOS Swift Testing remains unavailable because the CommandLineTools TestingMacros plugin is missing. Standalone macOS probes require no Testing plugin; the full Swift Testing suite ran in the installed Linux ARM64 Swift 6.4 container. The CI results below supplement those local checks; no clinical or complete release qualification is claimed.

## Fixture provenance and identity

`Tests/SwiftJLITests/ChromaReferenceFixtures.swift` is copied byte-for-byte from the supplied JLISwift branch. The synthetic generator is retained under `Tests/FixtureGenerators/`, with only its output directory adjusted for SwiftJLI. Its source records Pillow 12.3.0 / libjpeg-turbo 3.1.4.1 and per-fixture JPEG/RGB hashes. Tests have no runtime oracle dependency.

The new seven-line `centered-chroma-identity-macos-arm64.txt` is extracted from the fixed predecessor's 71-record identity run using SwiftJLI's unchanged synthetic generators/digest/identity support (with the module import changed to JLISwift in scratch). Every selected complete record matches the successor, and its encoded prefix matches the original fixture. The historical predecessor fixture remains byte-for-byte unchanged. This explicitly updates only the outputs corrected by this bug fix. [Source and fixture hashes](Qualification/JPEGDecodeParity/provenance.json) pin the evidence.

## Performance and memory — advisory, open release gate

Two interleaved before/after rounds on the same macOS ARM64 host, Release builds, scalar and automatic execution, 5 warm-ups and 20 timed decodes per case per round. Final table pools 40 timed decodes per case/backend. Input generation/encoding occurs outside the timed region; encoded byte counts are unchanged. Raw samples retain spread and p95 can be recomputed. These finite synthetic cases on a working developer machine are not the controlled representative release corpus.

| Image / backend | Before median ms | After median ms | Delta |
| --- | ---: | ---: | ---: |
| 512x512-yuv420 / automatic | 2.249 | 2.676 | +19.0% |
| 512x512-yuv420 / scalar | 2.867 | 3.477 | +21.3% |
| 512x512-yuv444 / automatic | 3.920 | 4.041 | +3.1% |
| 512x512-yuv444 / scalar | 4.758 | 5.168 | +8.6% |
| 513x509-yuv420 / automatic | 2.370 | 2.815 | +18.8% |
| 513x509-yuv420 / scalar | 2.897 | 3.361 | +16.0% |

Centred interpolation adds component rounding and extra algorithm workspace. The final 4:2:0 measurements are approximately 16–21% slower (about 0.4–0.6 ms per decode); the unchanged 4:4:4 control also varies, illustrating measurement noise. This cost is recorded, not waived. Further controlled performance/memory qualification remains necessary before a stable release. The initial scalar-only implementation was substantially slower and was replaced with bounded joined row workers.

Whole-process maximum RSS across these mixed encode/decode workloads: baseline 33,521,664–35,028,992 bytes; candidate 35,602,432–39,911,424 bytes. This is not isolated decoder workspace telemetry. The existing conservative resource admission remains in place; internal Float component planes are algorithm workspace, and final samples are still written directly into the caller's allocation. No extra full final-image hand-off copy is introduced. [Raw measurements and probe results](Qualification/JPEGDecodeParity/) are retained.

## Migration-completion audit and CI repair

The initial [CI run 38222503398](https://github.com/raster-labs/SwiftJLI/actions/runs/38222503398)
at `ba39fda` passed 10 of 13 jobs, including Linux Swift 6.4 on both architectures,
macOS ARM/Intel, separate macOS sanitizers, Apple SDK compilation and three
simulator jobs. It did not pass the whole matrix: Swift 6.2 could not type-check
one regression-test array expression, and the live iOS predecessor harness still
expected seven pre-fix decoded hashes. These failures are retained rather than
reported as missing environments or a complete pass.

Revision `c0c697f` names the invalid-stream array with an explicit `[[UInt8]]`
type and repairs the development-only live comparator. It checks all 71 encoded
records against both predecessor pins, 64 unchanged decoded records against the
original pin and exactly seven corrected records against v0.5.2 on the same
runtime. Both runs are required; no decoded record or encoder identity is waived.
The iOS workflow retains separate results for each pin and has time for both runs.
The shipping library is byte-identical to `ba39fda`.

[Requalification run 38240902748](https://github.com/raster-labs/SwiftJLI/actions/runs/38240902748)
is revision-bound to `c0c697f`. Its observed status and local follow-up checks are
recorded in [CompletionAudit.json](Qualification/CompletionAudit.json). Later checks
on the [pull request](https://github.com/raster-labs/SwiftJLI/pull/21/checks) are
separate executions; the snapshot is not a claim that pending jobs passed. At the
audit snapshot, all four Linux Swift 6.2/6.4 ARM64/x86_64 jobs passed; the Apple
requalification was still pending. The actual macOS comparator subsequently
passes both modes locally (exit 0): 71 encoded records in each run, plus 64
unchanged and seven corrected decoded records. The original lockfile is retained;
the maintenance mode selects its separately pinned revision only for that run.
The local Linux parity rerun passes all five test declarations, including all 15
independent fixture cases and both RGB precisions. A standalone comparator check
also rejects deliberately corrupted encoded and selected decoded records in each
mode. Historical test-source hashes describe the earlier run; they are not
silently rewritten after the test-only repair.

The [acceptance ledger](ACCEPTANCE.md) is the final status index. The implemented
fixes do not establish complete migration acceptance: controlled performance,
physical Watch validation, current-candidate fuzzing and affected workspace/oracle
qualification remain open. Main remains `a967d27`; this work is in draft PR #21.
