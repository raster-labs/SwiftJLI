# Final-candidate local validation — 3 November 2026

**Passed:** debug, release, full AddressSanitizer and full ThreadSanitizer runs
at `f548e5048e5c71204c2a2ec4036bf66c4f040285`, suite policy **0.10.0**.
Each run discovered and executed **389 test declarations in 60 suites**, with
**zero failures and zero skips**. The four executions are separate
configurations, not 1,556 distinct tests. The validator also completed clean and
incremental debug/release builds. All **22 recorded subprocess commands** exited
zero.

The recorded environment is Apple Swift **6.4.2**
(`swiftlang-6.4.2.1.9`, `clang-2100.4.1.1`), Xcode **27.2 (27B52)**,
native macOS ARM64, explicit **Swift Build**, and **two build jobs**. No build
engine fallback or package-sandbox disabling occurred. ASan and TSan used
separate debug build directories and separate executions; no sanitizer memory
figures are used as allocation evidence.

[report.json](report.json) is copied byte-for-byte from the completed run and
contains all exact subprocess arguments, source hashes, toolchain settings,
test discovery inventories, xUnit counts and exclusions.
[summary.json](summary.json) independently checks each retained xUnit file's
declaration/failure/skip counts and the recorded exits. Current shipping and
test files still matched their recorded hashes when archived. All 46 shipping
sources are identified, including the final `NativeExecution.swift` SHA-256
`695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`.
The recorded working tree includes unrelated documentation/evidence changes;
the source hashes identify the tested bytes.

The validation invocation completed with exit zero:

```sh
./Scripts/validate.sh --checks debug,release,asan,tsan --jobs 2 --timeout 1200 \
  --output /private/tmp/swiftjli-m5-callback-owner-validation
```

To reproduce, use the same source/toolchain and a **new** output directory.
The existing validator refuses an existing evidence directory. This archival
step did not execute another build or test.

## Retained evidence and limits

All 27 top-level raw report/log/XML files from the completed run are retained.
Larger log/XML files use lossless gzip with deterministic headers; small logs
and the report remain uncompressed. [archive-manifest.json](archive-manifest.json)
maps the report's original logical filenames to retained files and records both
original and compressed SHA-256 values. Decompress a `.gz` file to obtain the
exact original bytes. Large build trees and caches remain outside Git.

Swift Testing parameterised case executions differ from test declaration
counts; the raw report retains both without adding them together. No XCTest
source was discovered, so these are Swift Testing runs. Fixed-repetition,
consumer and SBOM checks were not selected in this command; the final
[remote consumer/SBOM record](../final-consumer-sbom/README.md) supplies its own
evidence. These local results do not establish hosted Swift 6.3.3 recovery,
other-platform execution, fuzz-campaign completion, performance acceptance,
physical-device qualification or stable-release approval.
