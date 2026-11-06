# SwiftJLI `v2.0.1` (`2.0.1`) — Release Gate Record

Executed on **6 November 2026** following [RELEASE.md](RELEASE.md), [SUITE_POLICY.md](SUITE_POLICY.md), and the owner's 6 November 2026 release directive (`VERSION` = `2.0.1`, shared contract = `0.10.0`, Apple OS deployment floor = `26.0`, Swift `6.2` tools minimum / Swift `6.4` qualified in Swift `6` language mode).

---

## 1. Release Versioning and Scope Directive

1. **Version Promotion (`2.0.1`)**: Tag `v2.0.0` was established on GitHub on `fb64081c077fcdddf24b64e806d3f6839828e988` prior to release metadata promotion. Per suite policy **POL-07** (*"Tags are never deleted or moved (POL-07). A defective release is followed by a patch release"*), `SwiftJLI v2.0.1` (`2.0.1`) ships as the authoritative first stable release with complete release metadata, manual, changelog, and verified release gates.
2. **Package Consumption**: Downstream consumers (including `DICOMKit` and independent applications) consume `SwiftJLI` via SemVer:
   ```swift
   .package(url: "https://github.com/raster-labs/SwiftJLI.git", from: "2.0.1")
   ```
3. **Core Scope in `2.0.1`**:
   - Pure-Swift JPEG implementation supporting ISO/IEC 10918-1 / ITU-T T.81 SOF0/SOF1/SOF2 (baseline, extended sequential, progressive DCT) and SOF3 (lossless and bounded-error near-lossless).
   - High-precision 2–16-bit sample preservation for medical, archival, and scientific imagery.
   - Pipelined and block-local greyscale reconstruction, compact DC entropy decoding, and Apple Accelerate hardware acceleration.
   - Zero-copy caller-owned `ImageDestination` decode path.
   - Complete `swiftjli-cli` tool implementing `capabilities`, `encode`, `decode`, `inspect`, and `validate` with fidelity-preserving NRRD (`CLI-04`) and binary Netpbm (PGM/PPM/PNM) I/O.

---

## 2. Verified Release Preconditions

| Precondition | Verification | Outcome |
| --- | --- | --- |
| **1. Continuous integration executes with non-zero steps** | Hosted GitHub Actions workflow `Codec and contract` (`.github/workflows/contract.yml`) executes with non-zero steps across multi-job matrix | **PASSED** |
| **2. Private vulnerability reporting enabled** | `gh api repos/raster-labs/SwiftJLI/private-vulnerability-reporting` checked 6 November 2026 | **PASSED** (`{"enabled": true}`) |
| **3. Explicit owner release assignment** | Owner release directive on 6 November 2026 authorising release and new version number | **PASSED** |

---

## 3. Executed Gates on the `2.0.1` Production Source Tree

Local gates executed serially on `arm64-apple-macosx` with `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)` (`Xcode 27.0 Build 27A266a`):

| Gate | Command / Action | Result |
| --- | --- | --- |
| **Shared contract SHA-256 manifest** | `(cd Documentation && shasum -a 256 -c COMMON_CONTRACT_SHA256.txt)` | **PASSED** (`7/7` shared contract files `OK`, contract `0.10.0`) |
| **Release-mode unit & regression suite** | `xcrun swift test -c release` | **PASSED** (`496` tests in `85` suites passed in `1.138s` with `0` failures, `0` skips) |
| **CLI conformance test suite** | `python3 Scripts/test-cli.py --binary .build/release/swiftjli-cli --output <scratch>` | **PASSED** (`252/252` black-box process checks passed) |
| **Staged CLI installation & UNIX manual** | `./Scripts/install-cli.sh --binary .build/release/swiftjli-cli --prefix /usr/local --destdir <stage>` | **PASSED** (executable installed, man page verified at `usr/local/share/man/man1/swiftjli-cli.1`) |
| **Independent package consumer** | `xcrun swift run --package-path Examples/IndependentConsumer` | **PASSED** (predictive, progressive, float, XYB, RGBA, YCbCr, and greyscale conversions verified) |
| **Codebase & Git tree guard** | Repository scan for patient data, secrets, and untracked files | **PASSED** (clean repository tree) |

---

## 4. Unexecuted and Deferred Gates (Disclosed Explicitly per Suite Policy)

Per suite policy (*"Anything unexecuted is recorded as unexecuted in the release notes, never as passed"*):

1. **Physical Watch testing**: **Unexecuted** (no physical Apple Watch connected to the release execution host; simulator qualification and software verification passed).
2. **Linux container matrix on release commit**: **Unexecuted locally** (Linux build matrix verified in preceding CI runs).
3. **Uninstalled Apple SDKs (`tvOS`, `visionOS`)**: **Unexecuted** on this host.
