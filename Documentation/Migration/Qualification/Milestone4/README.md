# Milestone 4 assessment — 13 October 2026

**Non-Watch scope qualified; physical Watch qualification pending hardware.**
The owner assigned completion of Milestone 4 and deferred Milestone 5. No
physical device is connected to this development host (`xcrun devicectl list
devices`: exit 0, `No devices found`). It would be incorrect to mark the whole
milestone complete from host tests or SDK compilation.

## Baseline and verified coverage

- Main: `e1ae85dff9da3fb150ef5fc6197be9756d8d4676`, the merge of PR #21.
  Its complete tree matches final PR head `abc0e87e3785426b36702bee9f098192a08bbe98`.
- Original migrated predecessor: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`;
  later maintenance pins remain in [JPEGDecodeParity.md](../../JPEGDecodeParity.md).
- Suite policy: 0.10.0. All seven common documents still match their existing
  SHA-256 manifest. No shipping source, public API, resource default, version,
  fixture or runtime dependency changes in this follow-up.
- [Post-merge CI 38355780498](https://github.com/raster-labs/SwiftJLI/actions/runs/38355780498)
  passed all 13 jobs; [job snapshot](main-ci.json) records the observed results.
  This is evidence for the baseline, not a CI claim for this follow-up commit.
- The [existing non-Watch qualification](../NonWatchCompletion/README.md)
  retains full fuzz campaigns, independent oracles, cross-codec storage,
  allocation/stress checks and controlled performance dispositions at their
  original source pins. These expensive checks were not relabelled as new runs.

## Work completed in this follow-up

The [WatchQualification package](../../../../Examples/WatchQualification/README.md)
adds six serial public-API tests with the existing Watch budgets, process memory
observations and elapsed times. It covers descriptor boundaries, 16 lossless
caller-storage round trips, eight concurrent-reader encodes, 16 DCT combinations
on this host, workspace rejection/recovery, eight callback cancellations and two
deadline failures. The macOS CI job now checks the harness as host validation.

| Executed check | Result |
| --- | --- |
| Debug harness on macOS ARM64 | Exit 0; 6 tests passed, no failures/skips |
| Release harness on macOS ARM64 | Exit 0; 6 tests passed, no failures/skips |
| Watch device SDK test-target compilation | Exit 0; arm64_32, watchOS 26 deployment floor; no device runtime executed |
| Deliberately incorrect expected sample (`XOR 1`) | Exit 1; the selected round-trip test failed; source restored and clean debug harness rerun passed |
| Existing common-document SHA-256 manifest | All 7 documents match |
| Physical device discovery | Exit 0; no connected devices |

[assessment.json](assessment.json) pins shipping and harness source hashes and
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
unchanged common documents. No new sanitizer, full codec benchmark or fuzz
campaign was required for a development test harness with unchanged shipping
code; the baseline's CI and separately pinned broad evidence remain applicable
within their documented scope.

## Remaining completion evidence

Run and review the harness on a supported physical Watch following its README.
Retain model/OS/toolchain/source details, signed test result, timing and memory
measurements, repeated work and error/cancellation/deadline results. Inspect
device memory under joined repeated work and expand boundary/profile coverage
where results expose a risk. The device run/signing procedure itself remains
unverified. Host process RSS includes the test runner, is cumulative and must
not be interpreted as measured Watch workspace or a validated device ceiling.
No new copy/allocator claim is inferred solely from operation reports.

Update this record and the acceptance ledger only after reviewing physical
evidence; revise defaults through the shared contract if required. The earlier
task excluded device testing; the current task leaves it pending availability,
not waived or silently moved into Milestone 5.

CLI payload verbs remain assigned to the separate CLI milestone by
[I3](../../../../IMPLEMENTATION.md#decisions-recorded-with-these-dispositions).
The diagnostic CLI is the accepted initial scope. Milestone 5, private-reporting
activation, stable tagging, application cutover and predecessor retirement are
not completed by this work. The existing SPDX generator/schema discrepancy
remains recorded in the release evidence.
