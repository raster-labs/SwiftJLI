# SwiftJLI `v2.1.0` (`2.1.0`) — Release Gate Record

Executed on **16 November 2026** following [RELEASE.md](RELEASE.md) and [SUITE_POLICY.md](SUITE_POLICY.md) (`POL-07`) (`VERSION` = `2.1.0`, `MIT` licence, Apple OS deployment floor = `26.0`, Swift `6.2` tools minimum / Swift `6.4` qualified in Swift `6` language mode), while keeping earlier published tags (`v2.0.0`, `v2.0.1`, `v2.0.2`, `v2.0.3`) immutable.

---

## 1. Release Versioning and Scope (`2.1.0`)

1. **SIMD8 Lossless Predictor, C11 24-Bit Lookahead RGB SV1 Row Leaf, Parallel `DRI` Strips & Zero-Hop Sync APIs (`370781a`, `f7b657b`, `ea257ff`, `04d356f`)**:
   - Adds `SIMD8` lossless JPEG (`SOF3`) predictor and de-interleave kernels, `BoundedParallelPool` multi-worker restart-interval (`DRI`) strip encoding/decoding with hardened `RawBitChunkWriter` 32-bit shift mask safety (`f7b657b`), a C11 24-bit Huffman lookahead lossless 3-channel RGB `SV1` row decoder leaf (`ea257ff`, with byte-stuffing, restart-marker, truncation, and cursor-parity regression coverage in `04d356f`), and zero-hop synchronous `encodeSynchronously` / `decodeSynchronously` entry points (`370781a`).
2. **Version & CLI Promotion (`2.1.0` / `v2.1.0`)**:
   - Promotes `VERSION`, `swiftjli-cli` (`Sources/SwiftJLICLI/main.swift`), and the section 1 manual (`ManPages/swiftjli-cli.1`) to `2.1.0` (`v2.1.0`).
   - Consumable via Swift Package Manager:
     ```swift
     .package(url: "https://github.com/raster-labs/SwiftJLI.git", from: "2.1.0")
     ```

---

## 2. Executed Gates on the `2.1.0` Release Candidate

| Gate | Command / Target | Result |
| --- | --- | --- |
| **Shared contract SHA-256 manifest** | `(cd Documentation && shasum -a 256 -c COMMON_CONTRACT_SHA256.txt)` | **PASSED** (`7/7` shared contract files `OK`) |
| **Native macOS ARM64 Release test suite** | `swift test -c release` | **PASSED** (`0` failures across all library, parallel `DRI`, and C11 lossless RGB SV1 parity suites) |
| **WatchQualification host harness** | `swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2` | **PASSED** (`6/6` tests passed) |
| **CLI conformance test suite & staged UNIX manual** | `python3 Scripts/test-cli.py --binary .build/release/swiftjli-cli --output /tmp/swiftjli-cli-210` | **PASSED** (`252/252` black-box process & staged install/manual checks passed) |
| **Independent package consumer** | `swift run --package-path Examples/IndependentConsumer` | **PASSED** (`Independent SwiftJLI consumer: predictive, progressive, float, XYB, RGBA, YCbCr and greyscale conversion passed.`) |

---

## 3. Unexecuted and Deferred Gates (Disclosed Explicitly per Suite Policy)

1. **Physical Watch testing**: **Unexecuted** (no physical Apple Watch connected to the release execution host; watchOS Simulator qualification and host harness checks passed).
