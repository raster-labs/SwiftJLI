# SwiftJLI

JPEG, including native lossless JPEG for the **Swift Image Compression Suite**.

**Status: codec migration in progress.** The common API now encodes, inspects and decodes unsigned SOF3 lossless and bounded-error JPEG (2–16 meaningful bits; greyscale and explicit RGB). Compatible interleaved storage supports padded rows and direct caller-destination decode. Explicit lossy mode now supports sequential and progressive DCT JPEG at 8/12-bit precision, with scalar execution and optional Apple Accelerate. Reduced-size decode, explicit raw greyscale Float32 output and both adaptive quantisation fields are available. Explicit normalised Float32 input can be clamped and quantised to 8-bit in lossy mode. Explicit sRGB-to-XYB encoding and direct sRGB integer decode are also available with matching ICC interpretation. Additional colour-output profiles and complete qualification remain open. See [current evidence and remaining work](Documentation/Migration/STATUS.md). No stable release or complete platform qualification is claimed.

SwiftJLI is the standalone successor to [JLISwift](https://github.com/Raster-Lab/JLISwift). The successor is intended to provide a harmonised API, explicit memory ownership, high-precision sample preservation and efficient shared-storage integration. It has no mandatory dependency on another suite library or CompressionFamily. Apache-2.0 licensing applies to these documents and subsequent authorised in-house implementation; third-party material retains its own terms.

## Swift 6.4 development candidate

Current development version: **1.1.0-dev.2** ([VERSION](VERSION)); shared contract **0.9.0**. This increments the earlier unreleased 1.0.0 target and creates no release/tag. See the [OS 27/CLI record](Documentation/Engineering/OS27CLI/README.md) for adopted features, exact Xcode/Swift Build evidence and open platform gates; its platform claims are superseded history, since contract 0.5.0 returned the Apple floor to 26.0 and the compiler minimum to 6.2, while its CLI content remains current. The historical [Milestone 1 evidence](Documentation/MILESTONE1.md) remains unchanged.

## Intended platform baseline

Swift 6.2 manifest minimum with Swift 6.4 as the qualified primary toolchain, Swift 6 language mode and complete concurrency checking. Apple OS deployment minima: macOS, iOS/iPadOS, tvOS, visionOS and watchOS 26.0. Apple Silicon is the primary optimisation target. macOS x86_64 and Linux ARM64/x86_64 are included with cleanly separated platform/architecture support. Ubuntu 24.04 is the initial Linux engineering baseline. These are requirements, not completed qualification claims.

## Start reading

The active migration builds on the completed API/storage foundation. See [migration status](Documentation/Migration/STATUS.md) and [historical foundation evidence](Documentation/MILESTONE1.md).

- [Coding-agent entry point](AGENTS.md) and [codec-specific implementation plan](IMPLEMENTATION.md).
- [Application migration guide: JLISwift → SwiftJLI](MIGRATION.md), including current limitations, API mappings and a staged cutover checklist for humans and coding agents.
- [Suite policy](Documentation/SUITE_POLICY.md) and [common API](Documentation/COMMON_API.md).
- [Memory ownership and no-copy hand-off](Documentation/MEMORY_CONTRACT.md).
- [Unit, regression and security testing](Documentation/TESTING.md).
- [Performance gates](Documentation/PERFORMANCE.md), [platforms](Documentation/PLATFORMS.md) and [CLI](Documentation/CLI_CONTRACT.md).
- [History and source provenance](HISTORY.md), [change log](CHANGELOG.md), [security](SECURITY.md), [contributing](CONTRIBUTING.md) and [Apache-2.0 licence](LICENSE).

## Relationship to the suite

The four independent libraries are SwiftJ2K, SwiftJLS, SwiftJXL and SwiftJLI, all intended to live under Raster-Lab. A future optional umbrella adapts them for codec selection and in-process transcoding. The codecs do not depend on that umbrella. SwiftCompressionFamily is not part of this successor plan. The common contract is mirrored documentation plus behavioural tests, not a shared runtime package.

The main module is `SwiftJLI`; the diagnostic CLI is `swiftjli-cli`. Feature coverage is being migrated and verified; see IMPLEMENTATION.md. Nothing here changes the predecessor repository's current maintenance configuration.

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

See the evidence for sandbox-compatible commands, sanitizer results and unexecuted platform gates. Performance and the full platform matrix remain qualification gates; Linux ARM64 tests and a local macOS build are recorded in the migration evidence.

## Command-line help and manual

The diagnostic CLI now provides `-h` / `--help`, `help <command>`, version and truthful capability reporting. Codec commands remain unavailable. Verbosity has five levels: `-v`, `-vv`, `--verbose 1..5`, `--verbose=+++` and `-verbose: 3`; diagnostics use stderr and `--quiet` suppresses optional messages. See [CLI usage and installation](CLI.md). The installer updates both the executable and its UNIX man page together. The CLI authorisation recorded in the [OS 27/CLI record](Documentation/Engineering/OS27CLI/README.md) stands; the OS 27 platform floor it was written against does not, having been reversed by contract 0.5.0 and confirmed at 26.0 by contract 0.9.0.
