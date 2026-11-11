# SwiftJLI

JPEG, including native lossless JPEG for the **Swift Image Compression Suite**.

**Status: stable release `2.0.3` (`v2.0.3`).**

The common API now encodes, inspects and decodes unsigned SOF3 lossless and bounded-error JPEG (2–16 meaningful bits; greyscale and explicit RGB). Compatible interleaved storage supports padded rows and direct caller-destination decode. Explicit lossy mode now supports sequential and progressive DCT JPEG at 8/12-bit precision, with scalar execution and optional Apple Accelerate. Reduced-size decode, explicit raw greyscale Float32 output and both adaptive quantisation fields are available. Explicit normalised Float32 input can be clamped and quantised to 8-bit in lossy mode. Explicit sRGB-to-XYB encoding and direct sRGB integer or explicitly normalised Float32 decode are also available with matching ICC interpretation. Explicit RGBA alpha discard, preconverted YCbCr input and RGB-to-greyscale conversion are implemented.

[PR #19](https://github.com/raster-labs/SwiftJLI/pull/19) merged on 9 October 2026 as `a967d27`; all 13 CI jobs passed on its tested source revision `a1920c7`. The three subsequent JPEG maintenance gaps are corrected in [PR #21](https://github.com/raster-labs/SwiftJLI/pull/21): centred chroma, raw RGB DCT and legal single-byte padding. PR #21 merged on 13 October 2026 as `e1ae85d`; the post-merge 13-job CI matrix passed. Executable non-Watch qualification includes the completed AC-powered rerun (140 exact output comparisons) with explicit measured performance trade-offs. GitHub private vulnerability reporting is active ([SECURITY.md](SECURITY.md)), and stable release `2.0.3` (`v2.0.3`) is published ([RELEASE-v2.0.3.md](Documentation/RELEASE-v2.0.3.md)); physical Watch device testing remains unexecuted (watchOS Simulator and host harness checks pass), and downstream application cutover remains a separate task. See the [acceptance ledger](Documentation/Migration/ACCEPTANCE.md) for exact evidence revisions, limitations and deferred work, and [non-Watch qualification](Documentation/Migration/Qualification/NonWatchCompletion/README.md) for the refreshed evidence.

SwiftJLI is the standalone successor to [JLISwift](https://github.com/Raster-Lab/JLISwift). The successor provides a harmonised API, explicit memory ownership, high-precision sample preservation and efficient shared-storage integration. It has no mandatory dependency on another suite library or CompressionFamily. MIT licensing applies to these documents and subsequent authorised in-house implementation; third-party material retains its own terms.

Milestone 4 software — including `swiftjli-cli` payload commands (`encode`, `decode`, `inspect`, `validate`) and fidelity-preserving NRRD (`CLI-04`) and binary Netpbm (`pgm`/`ppm`/`pnm`) I/O — is implemented and qualified alongside the [v2.0.1](Documentation/RELEASE-v2.0.1.md), [v2.0.2](Documentation/RELEASE-v2.0.2.md) and [v2.0.3](Documentation/RELEASE-v2.0.3.md) release gates across native macOS and the Apple Simulator matrix (`iOS`, `tvOS`, `watchOS` and `visionOS`). The [Watch qualification harness](Examples/WatchQualification/README.md) prepares the device checks; no physical Watch is connected to the current development host, so physical Watch device testing remains explicitly recorded as unexecuted ([Milestone 4 status and evidence](Documentation/Migration/Qualification/Milestone4/README.md)).

## Current version

Current stable version: **2.0.3** ([VERSION](VERSION)); shared suite policy **0.10.0**. Consumable via Swift Package Manager:

```swift
.package(url: "https://github.com/raster-labs/SwiftJLI.git", from: "2.0.3")
```

## Intended platform baseline

Swift 6.2 manifest minimum with Swift 6.4 as the qualified primary toolchain, Swift 6 language mode and complete concurrency checking. Apple OS deployment minima: macOS, iOS/iPadOS, tvOS, visionOS and watchOS 26.0. Apple Silicon is the primary optimisation target. macOS x86_64 and Linux ARM64/x86_64 are included with cleanly separated platform/architecture support. Ubuntu 24.04 is the initial Linux engineering baseline. These are requirements, not completed qualification claims.

## Start reading

The merged codec builds on the completed API/storage foundation. Read the [current acceptance ledger](Documentation/Migration/ACCEPTANCE.md) first; [migration checkpoints](Documentation/Migration/STATUS.md) and [foundation evidence](Documentation/MILESTONE1.md) retain historical results.

The latest [JPEG performance and memory report](Documentation/Migration/Qualification/DjpegPerformanceRound5_20261103/block-local-6e763ec/README.md) records exact ARM64 block-local DCT, smaller scratch windows and lossless entropy improvements, including a repaired concurrency defect. Fresh comparisons show lower library latency in 11 of 12 eligible cases and lower dense/noisy DCT RSS by about 0.5–0.8 MiB versus the preceding SwiftJLI build. All eight large lossless CLI cases beat both pinned djpeg versions in two provisional rounds. Small CLI latency, single-worker DCT and DCT/process memory remain open gaps; the overall optimisation goal is not complete.

- [Coding-agent entry point](AGENTS.md) and [codec-specific implementation plan](IMPLEMENTATION.md).
- [Application migration guide: JLISwift → SwiftJLI](MIGRATION.md), including current limitations, API mappings and a staged cutover checklist for humans and coding agents.
- [Suite policy](Documentation/SUITE_POLICY.md) and [common API](Documentation/COMMON_API.md).
- [Memory ownership and no-copy hand-off](Documentation/MEMORY_CONTRACT.md).
- [Unit, regression and security testing](Documentation/TESTING.md).
- [Performance gates](Documentation/PERFORMANCE.md), [platforms](Documentation/PLATFORMS.md) and [CLI](Documentation/CLI_CONTRACT.md).
- [History and source provenance](HISTORY.md), [change log](CHANGELOG.md), [security](SECURITY.md), [contributing](CONTRIBUTING.md) and [MIT licence](LICENSE).

## Relationship to the suite

The four independent libraries are SwiftJ2K, SwiftJLS, SwiftJXL and SwiftJLI, all intended to live under Raster-Lab. A future optional umbrella adapts them for codec selection and in-process transcoding. The codecs do not depend on that umbrella. SwiftCompressionFamily is not part of this successor plan. The common contract is mirrored documentation plus behavioural tests, not a shared runtime package.

The main module is `SwiftJLI`; the command-line executable is `swiftjli-cli`. Implemented coverage and explicit product deferrals are recorded in IMPLEMENTATION.md. Nothing here changes the predecessor repository's current maintenance configuration.

## Synthetic storage example

This API stores ordinary unsigned sample words. It does not create a compressed image or claim JPEG interoperability.

```swift
import SwiftJLI

let descriptor = try SwiftJLI.ImageDescriptor.greyscale16(
    width: 3, height: 2, meaningfulBits: 16, rowBytes: 8)
let destination = try SwiftJLI.ImageDestination.allocate(descriptor: descriptor)
let image = try destination.writeUInt16 { x, y in
    [UInt16(0), 65535, 4095, 17, 1, 32768][y * 3 + x]
}
let value = try image.sampleUInt16(x: 1, y: 0) // 65535
```

The [independent consumer](Examples/IndependentConsumer) compiles and runs this ownership pattern and the common encoder/decoder call shapes using only this package. Raw `withUnsafeBytes` and mutable-fill closures are advanced boundaries: pointers must not escape or be shared with asynchronous work. Prefer the checked sample helpers for ordinary access.

To run headless with the installed Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

See the evidence for sandbox-compatible commands, sanitizer results and unexecuted platform gates. The merged baseline passes Linux Swift 6.2/6.4 ARM64/x86_64, macOS ARM/Intel runtime checks, separate macOS sanitizers, Apple SDK compilation and four Apple simulator suites. Performance is qualified for the recorded matrix; physical Watch resource validation remains open; simulator success does not establish device memory ceilings.

## Command-line tool and manual

`swiftjli-cli` provides `-h` / `--help`, `help <command>`, `--version`, `--capabilities` and the payload commands `encode`, `decode`, `inspect` and `validate` with fidelity-preserving NRRD (`CLI-04`) and binary Netpbm (`pgm`/`ppm`/`pnm`) I/O. Verbosity has five levels: `-v`, `-vv`, `--verbose 1..5`, `--verbose=+++` and `-verbose: 3`; diagnostics use stderr and `--quiet` suppresses optional messages. See [CLI usage and installation](CLI.md). The installer updates both the executable and its UNIX man page together. The CLI authorisation recorded in the [OS 27/CLI record](Documentation/Engineering/OS27CLI/README.md) stands; the OS 27 platform floor it was written against does not, having been reversed by contract 0.5.0 and confirmed at 26.0 by contract 0.9.0.
