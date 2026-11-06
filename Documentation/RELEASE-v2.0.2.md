# SwiftJLI `v2.0.2` (`2.0.2`) — Release Gate Record

Executed on **6 November 2026** following [RELEASE.md](RELEASE.md), [SUITE_POLICY.md](SUITE_POLICY.md) (`POL-07`), and the owner's directive to rerun and resolve the failed test cases in the release (`VERSION` = `2.0.2`, shared contract = `0.10.0`, Apple OS deployment floor = `26.0`, Swift `6.2` tools minimum / Swift `6.4` qualified in Swift `6` language mode).

---

## 1. Root Cause and Patch Scope (`2.0.2`)

1. **Apple Simulator Runtime Test Failures (`BlockLocalIDCTTests` & `PipelinedGreyscaleTests`)**:
   - In `v2.0.1` (`df8cd33`), `BlockLocalIDCT.available` was gated on `#if canImport(Accelerate) && arch(arm64)`.
   - While `BlockLocalIDCT` (8-element ascending `SIMD8<Float>.addingProduct` FMA accumulation) is bit-for-bit identical to Accelerate's `vDSP_mmul` across all batch sizes on native `macOS` ARM64, the `iOS`, `tvOS`, `watchOS`, and `visionOS` Simulator Accelerate runtime uses an internal `vDSP_mmul(8, 8192, 8)` kernel at `blocks >= 1024` (`eightN >= 8192`) that differs by 1 ULP in `Float` from the 8-element ascending FMA loop.
   - Scoping `BlockLocalIDCT.available` in `Sources/SwiftJLI/Native/Platform/BlockLocalIDCT.swift` to `#if canImport(Accelerate) && os(macOS) && arch(arm64)` ensures non-macOS and simulator runtimes execute the canonical `AccelerateDSP.inverseDCTBatchDequantized` GEMM path across all batch sizes and worker counts while preserving `BlockLocalIDCT` on macOS ARM64.
2. **CI `macOS 26 / Xcode default Swift` Timeout Headroom**:
   - In `.github/workflows/contract.yml`, the `macos` job runs Debug build/test, Release build/test, Address Sanitizer (`--sanitize address`), Thread Sanitizer (`--sanitize thread`), and `Examples/WatchQualification` sequentially (~30m 20s total on hosted `macos-26` runners), causing the job to be cancelled at the 30-minute boundary after all 496 TSan tests had already passed.
   - Increased `timeout-minutes` on `macos` from `30` to `45` (matching `ios-simulator`).

---

## 2. Executed Gates and Rerun Evidence on `2.0.2`

| Gate | Command / Target | Result |
| --- | --- | --- |
| **Shared contract SHA-256 manifest** | `(cd Documentation && shasum -a 256 -c COMMON_CONTRACT_SHA256.txt)` | **PASSED** (`7/7` shared contract files `OK`, contract `0.10.0`) |
| **Native macOS ARM64 Release test suite** | `xcrun swift test -c release` | **PASSED** (`496` tests in `85` suites passed with `0` failures) |
| **iOS Simulator full library suite** | `xcrun xcodebuild test -scheme SwiftJLI-Package -destination "platform=iOS Simulator,id=9021546C-CD90-4663-A01B-B4E92851C3DF"` | **PASSED** (`496` tests in `85` suites passed with `0` failures) |
| **iOS Simulator predecessor comparison** | `python3 Scripts/test-apple-simulator.py --package-path Examples/PredecessorComparison --scheme PredecessorComparison` (default & `JLISWIFT_CENTERED_REFERENCE=1`) | **PASSED** (both runs passed on iOS Simulator) |
| **tvOS Simulator runtime rerun** | `xcrun xcodebuild test -scheme SwiftJLI-Package -destination "platform=tvOS Simulator,id=3ED74F7E-454E-41DF-8DC8-825EDEE4DA82"` (`BlockLocalIDCTTests`, `PipelinedGreyscaleTests`, `ParallelGreyscaleWindowTests`, `CACPublicPipelineTests`, `StreamingWorkspaceAdmissionTests`) | **PASSED** (`0` failures) |
| **watchOS Simulator runtime rerun** | `xcrun xcodebuild test -scheme SwiftJLI-Package -destination "platform=watchOS Simulator,id=1FEFBD8C-164D-44F4-A940-88ECE79574DE"` (`BlockLocalIDCTTests`, `PipelinedGreyscaleTests`, `ParallelGreyscaleWindowTests`, `CACPublicPipelineTests`, `StreamingWorkspaceAdmissionTests`) | **PASSED** (`0` failures) |
| **visionOS Simulator runtime rerun** | `xcrun xcodebuild test -scheme SwiftJLI-Package -destination "platform=visionOS Simulator,id=9D9B3976-E27A-490B-906D-D98B412251BD"` (`BlockLocalIDCTTests`, `PipelinedGreyscaleTests`, `ParallelGreyscaleWindowTests`, `CACPublicPipelineTests`, `StreamingWorkspaceAdmissionTests`) | **PASSED** (`0` failures) |
| **WatchQualification host harness** | `xcrun swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2` | **PASSED** (`6/6` tests passed in `0.138s`) |
| **CLI conformance test suite** | `python3 Scripts/test-cli.py --binary .build/release/swiftjli-cli --output /tmp/cli-release-202.json` | **PASSED** (`252/252` black-box process checks passed) |
| **Staged CLI installation & UNIX manual** | `./Scripts/install-cli.sh --binary .build/release/swiftjli-cli --prefix /usr/local --destdir <stage>` | **PASSED** (`swiftjli-cli` `2.0.2` and `swiftjli-cli.1` verified) |
| **Independent package consumer** | `xcrun swift run --package-path Examples/IndependentConsumer` | **PASSED** |

---

## 3. Unexecuted and Deferred Gates (Disclosed Explicitly per Suite Policy)

Per suite policy (*"Anything unexecuted is recorded as unexecuted in the release notes, never as passed"*):

1. **Physical Watch testing**: **Unexecuted** (no physical Apple Watch connected to the release execution host; watchOS Simulator qualification and host harness checks passed).
