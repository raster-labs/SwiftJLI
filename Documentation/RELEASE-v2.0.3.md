# SwiftJLI `v2.0.3` (`2.0.3`) — Release Gate Record

Executed on **11 November 2026** following [RELEASE.md](RELEASE.md), [SUITE_POLICY.md](SUITE_POLICY.md) (`POL-07`), and the owner's 11 November 2026 directive to publish and tag a release on a preserved GitHub release branch (`VERSION` = `2.0.3`, branch = `codex/release-2.0.3`, shared contract = `0.10.0`, Apple OS deployment floor = `26.0`, Swift `6.2` tools minimum / Swift `6.4` qualified in Swift `6` language mode).

---

## 1. Release Versioning and Scope (`2.0.3`)

1. **MIT Licence Restoration (`POL-07`)**:
   - Following the owner's 10 November 2026 decision (`POL-07` in [SUITE_POLICY.md](SUITE_POLICY.md), merged in [PR #31](https://github.com/raster-labs/SwiftJLI/pull/31) as `97a50ee`), `SwiftJLI v2.0.3` (`2.0.3`) ships the MIT-licensed repository (`Copyright (c) 2026 Raster Images Private Limited`), removing the interim Apache-2.0 `LICENSE`/`NOTICE` from contract `0.8.0` and updating in-house `SPDX-License-Identifier` headers across `Package.swift`, `Sources/`, `Tests/`, `Scripts/` and `Examples/` (`209` files) to `MIT`.
   - Third-party assets (`sRGB2014.icc` / `ICC-LICENSE.txt` and `UpstreamJPEG` fixtures), historical qualification archives, and earlier published tags (`v2.0.0`, `v2.0.1`, `v2.0.2`) remain unmodified per `POL-07`.
2. **Version & CLI Promotion (`2.0.3` / `v2.0.3`)**:
   - Promotes `VERSION`, `swiftjli-cli` (`Sources/SwiftJLICLI/main.swift`), and the section 1 manual (`ManPages/swiftjli-cli.1`) to `2.0.3` (`v2.0.3`).
   - Preserves the complete public `SwiftJLI` codec surface and `swiftjli-cli` executable behavior unchanged from `2.0.2`.
   - Consumable via Swift Package Manager:
     ```swift
     .package(url: "https://github.com/raster-labs/SwiftJLI.git", from: "2.0.3")
     ```

---

## 2. Verified Release Preconditions

| Precondition | Verification | Outcome |
| --- | --- | --- |
| **1. Continuous integration executes with non-zero steps** | Hosted GitHub Actions workflow `Codec and contract` (`.github/workflows/contract.yml`) passed all 13 jobs on `97a50ee` ([run 42815176392](https://github.com/raster-labs/SwiftJLI/actions/runs/42815176392)) | **PASSED** |
| **2. Private vulnerability reporting enabled** | `gh api repos/raster-labs/SwiftJLI/private-vulnerability-reporting` checked 11 November 2026 | **PASSED** (`{"enabled": true}`) |
| **3. Explicit owner release assignment** | Owner release directive on 11 November 2026 authorising release `2.0.3` (`v2.0.3`) and preserving release branch `codex/release-2.0.3` on GitHub | **PASSED** |

---

## 3. Executed Gates on the `2.0.3` Release Candidate

Local gates executed serially on `arm64-apple-macosx` with `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`:

| Gate | Command / Target | Result |
| --- | --- | --- |
| **Shared contract SHA-256 manifest** | `(cd Documentation && shasum -a 256 -c COMMON_CONTRACT_SHA256.txt)` | **PASSED** (`7/7` shared contract files `OK`, contract `0.10.0`) |
| **Native macOS ARM64 Release test suite** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test -c release` | **PASSED** (`496` tests in `85` suites passed in `1.257s` with `0` failures) |
| **WatchQualification host harness** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2` | **PASSED** (`6/6` tests passed in `0.133s` with `0` failures) |
| **CLI conformance test suite** | `python3 Scripts/test-cli.py --binary .build/release/swiftjli-cli --output /tmp/swiftjli-cli-203` | **PASSED** (`252/252` black-box process checks passed) |
| **Staged CLI installation & UNIX manual** | `./Scripts/install-cli.sh --binary .build/release/swiftjli-cli --prefix /usr/local --destdir /tmp/swiftjli-stage-203` | **PASSED** (`swiftjli-cli` `2.0.3` and `swiftjli-cli.1` verified) |
| **Independent package consumer** | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run --package-path Examples/IndependentConsumer` | **PASSED** (`Independent SwiftJLI consumer: predictive, progressive, float, XYB, RGBA, YCbCr and greyscale conversion passed.`) |

---

## 4. Unexecuted and Deferred Gates (Disclosed Explicitly per Suite Policy)

Per suite policy (`POL-08` — *"Anything unexecuted is recorded as unexecuted in the release notes, never as passed"*):

1. **Physical Watch testing**: **Unexecuted** (no physical Apple Watch connected to the release execution host; watchOS Simulator qualification and host harness checks passed).
2. **Downstream application cutover (`DICOMKit`)**: **Deferred** to separate consumer-repository tasks.
