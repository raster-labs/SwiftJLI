# Milestone 4 assessment — 15 October 2026

**Milestone 4 software and owner-scoped macOS + iOS Simulator validation complete; physical Watch qualification pending hardware.**
On 15 October 2026, from baseline `0aa2e5287056a6508e0474b927f3bd4d7bbf7cfe`, the owner assigned completion of all Milestone 4 software work — reconciling the historical `I3` deferral to implement `encode`, `decode`, `inspect` and `validate` in `swiftjli-cli` — and explicitly limited platform validation for this task to **native macOS and the iOS Simulator** ("Use the iOS simulator"). Physical devices, Watch, tvOS, visionOS and fresh Linux host runs are outside this task's execution scope; Milestone 5 remains deferred. No physical device is connected to this development host (`xcrun devicectl list devices`: exit 0, `No devices found`), so full hardware release completion remains pending physical Watch execution.

## 15 October 2026 — CLI payload implementation and macOS / iOS Simulator qualification

- **Baseline and source pins**: Branched from `0aa2e5287056a6508e0474b927f3bd4d7bbf7cfe` on `codex/milestone-4-complete`. All 130 library, package and test files are byte-identical to `0aa2e52` ([CLIAudit/audit-candidate-c/source-manifest.json](CLIAudit/audit-candidate-c/source-manifest.json)). `Sources/SwiftJLICLI/main.swift` is at audited SHA-256 `0a89847246fea61330cba603dd530939781fca591aef739c64727645b7a40ce8` (release binary SHA-256 `9860a825d583b3f239194d557c6e8cce273df730bddcc2277856af2443ebb834`).
- **Environment**: macOS 27.0.1 (`26A434`) on Apple Silicon (`arm64`), Xcode 27.0 (`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), iOS 26.0 Simulator (`iPhone 17 Pro`, UDID `9021546C-CD90-4663-A01B-B4E92851C3DF`), and independent comparator `libjpeg-turbo` 3.2.0 (`build 20260630`). CLI tests run on native macOS ARM64; the iOS 26.0 Simulator runs the `SwiftJLITests` library suite.
- **Implemented CLI surface (`I3` reconciled)**:
  - `encode`, `decode`, `inspect` and `validate` implemented in `Sources/SwiftJLICLI/main.swift` per `CLI_CONTRACT.md` (v0.10.0), with updated UNIX manual (`ManPages/swiftjli-cli.1`, verified clean under `mandoc -T lint`) and usage guide ([CLI.md](../../../../CLI.md)).
  - **NRRD sample-interchange profile (`CLI-04`, [NRRD format specification](https://teem.sourceforge.net/nrrd/format.html))**: Attached raw 2D single-component unsigned 16-bit greyscale (`dimension: 2`, `sizes: <width> <height>`, `type: uint16`/`ushort`/`unsigned short`/`uint16_t`, `encoding: raw`, `endian: little`|`big`, optional spatial `kinds: domain domain` or `space space`). Interchanges exact unscaled unsigned 16-bit integers (`0...65535`). Rejects all `key:=value` metadata, detached data files, skip directives, non-spatial `kinds` and any unknown `field: value` lines with static diagnostics (exit `4`) so semantic metadata is never silently dropped and untrusted header text is never echoed to `stderr`.
  - **Netpbm sample-interchange profile ([PGM](https://netpbm.sourceforge.net/doc/pgm.html) / [PPM](https://netpbm.sourceforge.net/doc/ppm.html) specifications)**: Binary `P5` (1-component greyscale) and `P6` (3-component RGB) with explicit `maxval = (1 << meaningfulBits) - 1` for `2...16` meaningful bits (1 byte per sample for `2...8` bits, big-endian 2 bytes per sample for `9...16` bits). Samples are interchanged as direct integer values in `0...maxval` with no gamma or ITU-R BT.709 transfer conversion and no sample scaling; non-power-of-two-minus-one `maxval` values reject with exit `4`, and samples exceeding `maxval` reject with exit `3`. Every dimension product is checked with overflow-reporting arithmetic and admitted against `ResourceLimits` before allocation.
  - **Codec hand-off counters vs shell serialisation**: `copyEventCount`, `pixelAllocationCount`, `peakPixelBytes` and `peakWorkspaceBytes` report the library codec's `OperationReport` (with unavailable telemetry preserved as JSON `null` or `"unknown"` in text rather than `0`) and are distinct from the CLI shell's file/stream parsing and serialisation buffers. Simultaneously retained CLI buffers (`rawInput + sourceImage` on encode, `decoded.image + outBytes` on decode) are bounded together under `--max-memory`, raw input is released before encoding or after decoding, and serialised output capacity is preflighted.
  - **Nonblocking stream I/O, atomic publication and deadline classification**: Stream I/O (`-i -` / `-o -`) sets `O_NONBLOCK`, retries `EAGAIN`/`EWOULDBLOCK` via bounded `poll` slices against the command-wide monotonic deadline (`--timeout`), and restores inherited blocking flags in `defer`; named non-regular inputs (such as FIFOs) are rejected without blocking with exit `6`. Regular file outputs stage to a sibling temporary file and recheck cancellation and deadline immediately before atomic `link`/`rename` publication; streaming `-o -` pipe writes cannot retract bytes already flushed before a downstream pipe close, timeout or signal, and exit non-zero (`5`, `6` or `130`). In `runAsync`, explicit `SIGINT`/`SIGTERM` exits `130` while command-deadline expiry is translated to `CodecError(.resourceLimitExceeded)` (exit `5`).

| Executed check (15 October 2026) | Target platform | Result | Evidence |
| --- | --- | --- | --- |
| Native macOS ARM64 release library suite (`SwiftJLITests`) | Native macOS ARM64 | Exit 0; 354 tests in 50 suites passed | [CLIAudit/audit-platform-results.json](CLIAudit/audit-platform-results.json), [CLIAudit/audit-library-release-a.log](CLIAudit/audit-library-release-a.log) (SHA-256 `a5c9577a...`) |
| iOS 26.0 Simulator library suite (`SwiftJLITests`, `iPhone 17 Pro`) | iOS 26.0 Simulator | Exit 0; 354 tests in 50 suites passed | [CLIAudit/audit-platform-results.json](CLIAudit/audit-platform-results.json), [CLIAudit/audit-ios26.log.gz](CLIAudit/audit-ios26.log.gz) (uncompressed SHA-256 `60817de3...`, `.gz` SHA-256 `3771836b...`) |
| CLI process, help, manual, staged install & codec deadline sweep (`Scripts/test-cli.py`, SHA-256 `95bb0e7b...`) | Native macOS ARM64 | Exit 0; 203 process checks passed (197 in candidate-C audit + 6-command codec deadline duration sweep `[5, 5, 5, 5, 5, 5]`) | [CLIAudit/process-final-203/report.json](CLIAudit/process-final-203/report.json), [CLIAudit/process-candidate-c/report.json](CLIAudit/process-candidate-c/report.json), [CLIAudit/retained-deadline-control/report.json](CLIAudit/retained-deadline-control/report.json) |
| Independent `libjpeg-turbo` 3.2.0 `UInt16` NRRD/JPEG interchange | Native macOS ARM64 | Exit 0; 29 commands, 23 assertions passed | [CLIAudit/interop-candidate-c/report.json](CLIAudit/interop-candidate-c/report.json) |
| Independent Netpbm/lossless/DCT/near-lossless profiles | Native macOS ARM64 | Exit 0; 93 commands, 46 assertions passed | [CLIAudit/profiles-candidate-c/report.json](CLIAudit/profiles-candidate-c/report.json) |
| Stream deadline, cancellation, backpressure, FIFO & descriptor lifecycle | Native macOS ARM64 | Exit 0; 5 commands, 9 assertions passed | [CLIAudit/io-candidate-c/report.json](CLIAudit/io-candidate-c/report.json) |
| Codec deadline exit-category verification (512×512 RGB progressive scalar encode) | Native macOS ARM64 | Exit 0; 6 commands passed with exit codes `[5, 5, 5, 5, 5, 0]` (5 deadline exits with code `5` and 1 completed encode with code `0`; never `130`) | [CLIAudit/codec-deadline-candidate-c/report.json](CLIAudit/codec-deadline-candidate-c/report.json) |
| Common-contract SHA-256 digests and whitespace check | Host repository | Exit 0; all 7 shared contract digests match | [CLIAudit/audit.json](CLIAudit/audit.json) |

### Retained failed attempts and audit iterations

- **Sandboxed compiler module cache**: Initial isolated `swift build` inside the tool sandbox could not write `/var/folders/.../C/clang/ModuleCache` (`[CLIAudit/audit-build-a.log](CLIAudit/audit-build-a.log)`); building with normal host module-cache access succeeded (`[CLIAudit/audit-build-a-unsandboxed.log](CLIAudit/audit-build-a-unsandboxed.log)`).
- **Pipe descriptor flag control**: The first I/O audit script (`[CLIAudit/io-candidate-b/runner-failed.py](CLIAudit/io-candidate-b/runner-failed.py)`, `[CLIAudit/io-candidate-b/report.json](CLIAudit/io-candidate-b/report.json)`) compared the entire `fcntl(F_GETFL)` word (`1` vs `65537`). A direct Python `os.write` control (`[CLIAudit/io-descriptor-control.json](CLIAudit/io-descriptor-control.json)`) demonstrated that macOS sets kernel pipe status bits on any write while `O_NONBLOCK` (`4`) is `0` before and after; the corrected check (`[CLIAudit/io-candidate-b-corrected/report.json](CLIAudit/io-candidate-b-corrected/report.json)`) verifies the `O_NONBLOCK` bit.
- **Candidate B codec deadline classification and regression sweep**: Candidate B (`[CLIAudit/audit-candidate-b/source-manifest.json](CLIAudit/audit-candidate-b/source-manifest.json)`) cancelled the worker task when the command deadline expired in `runAsync` and returned `CancellationError` (exit `130`) instead of `resourceLimitExceeded` (exit `5`) on a 512×512 RGB progressive scalar encode with `--timeout 0.01` (`[CLIAudit/codec-deadline-candidate-b/dct-report.json](CLIAudit/codec-deadline-candidate-b/dct-report.json)`). Candidate C (`[CLIAudit/audit-candidate-c/source-manifest.json](CLIAudit/audit-candidate-c/source-manifest.json)`) checks `interrupted` first after joining work, then checks `context.check()`, and translates non-signal task cancellation to `CodecError(.resourceLimitExceeded)` (`[CLIAudit/codec-deadline-candidate-c/report.json](CLIAudit/codec-deadline-candidate-c/report.json)`). A single 5 ms trial in `Scripts/test-cli.py` can expire before codec entry (`[CLIAudit/retained-deadline-control/report.json](CLIAudit/retained-deadline-control/report.json)` shows `[130, 5, 5]` on candidate B vs `[5, 5, 5]` on candidate C), so `Scripts/test-cli.py` (SHA-256 `95bb0e7b99688af21f4ed6b528ece11799362ee09c7ac231b8b4be773597d815`) uses the audited 6-command duration sweep (`0.005`, `0.01`, `0.015` seconds twice), allowing completed-before-deadline exit `0` with valid JPEG output or deadline exit `5` with no output, rejecting exit `130` in every trial, and requiring at least one deadline exit `5` (`[CLIAudit/process-final-203/report.json](CLIAudit/process-final-203/report.json)`).

---

## 13 October 2026 — Watch harness preparation and baseline coverage

- Main: `e1ae85dff9da3fb150ef5fc6197be9756d8d4676`, the merge of PR #21.
  Its complete tree matches final PR head `abc0e87e3785426b36702bee9f098192a08bbe98`.
- Original migrated predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`;
  later maintenance pins remain in [JPEGDecodeParity.md](../../JPEGDecodeParity.md).
- Suite policy: 0.10.0. All seven common documents still match their existing
  SHA-256 manifest.
- [Post-merge CI 38355780498](https://github.com/raster-labs/SwiftJLI/actions/runs/38355780498)
  passed all 13 jobs; [job snapshot](main-ci.json) records the observed results.
  This is evidence for the baseline, not a CI claim for later commits.
- The [existing non-Watch qualification](../NonWatchCompletion/README.md)
  retains full fuzz campaigns, independent oracles, cross-codec storage,
  allocation/stress checks and controlled performance dispositions at their
  original source pins. These expensive checks were not relabelled as new runs.

### Watch harness checks completed on 13 October 2026

The [WatchQualification package](../../../../Examples/WatchQualification/README.md)
adds six serial public-API tests with the existing Watch budgets, process memory
observations and elapsed times. It covers descriptor boundaries, 16 lossless
caller-storage round trips, eight concurrent-reader encodes, 16 DCT combinations
on this host, workspace rejection/recovery, eight callback cancellations and two
deadline failures. The macOS CI job checks the harness as host validation.

| Executed check | Result |
| --- | --- |
| Debug harness on macOS ARM64 | Exit 0; 6 tests passed, no failures/skips |
| Release harness on macOS ARM64 | Exit 0; 6 tests passed, no failures/skips |
| Watch device SDK test-target compilation | Exit 0; arm64_32, watchOS 26 deployment floor; no device runtime executed |
| Deliberately incorrect expected sample (`XOR 1`) | Exit 1; the selected round-trip test failed; source restored and clean debug harness rerun passed |
| Existing common-document SHA-256 manifest | All 7 documents match |
| Physical device discovery | Exit 0; no connected devices |

[assessment.json](assessment.json) pins the 13 October shipping and harness source hashes and
keeps all twelve host measurement records. Raw test/build logs are retained
alongside it; the absolute repository path is normalised to `<repository>`.
`xcode.log`, `swift.log` and `os.log` record the exact local environment. The
negative control changes test expectations only, never shipping codec code.

Commands from the repository root (logs redirected to fresh evidence files):

```sh
swift test --package-path Examples/WatchQualification --disable-xctest -j 2
swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2
swift build --package-path Examples/WatchQualification --target WatchQualificationTests \
  -c release -j 2 --triple arm64_32-apple-watchos26.0 \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk \
  --scratch-path .build/watch-qualification-device
# With the documented negative test-expectation mutation, then restore source:
swift test --package-path Examples/WatchQualification --disable-xctest -j 2 \
  --filter repeatedLosslessCallerStorage
xcrun devicectl list devices
git diff --check
```

From `Documentation`, `shasum -a 256 -c COMMON_CONTRACT_SHA256.txt` verifies the
unchanged common documents.

## Remaining hardware release evidence

Physical Watch hardware was outside the owner's 15 October 2026 macOS + iOS Simulator validation scope and remains unexecuted for full stable-release completion. When hardware is available, run and review the harness on a supported physical Watch following its README. Retain model/OS/toolchain/source details, signed test result, timing and memory measurements, repeated work and error/cancellation/deadline results. Host process RSS includes the test runner, is cumulative and must not be interpreted as measured Watch workspace or a validated device ceiling. No new copy/allocator claim is inferred solely from operation reports.

Milestone 5, private-reporting activation, stable tagging, application cutover and predecessor retirement are not completed by this work. The existing SPDX generator/schema discrepancy remains recorded in the release evidence.
