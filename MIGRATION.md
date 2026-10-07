# Migrating applications from JLISwift to SwiftJLI

The migration is in progress. The public API currently supports native SOF3 lossless/bounded-error and SOF0/SOF1/SOF2 lossy JPEG; advanced predecessor profiles and full qualification remain open. Keep each production use case on its qualified predecessor until its successor profile passes acceptance. [Current evidence and open requirements](Documentation/Migration/STATUS.md) distinguish implementation from qualification.

The source pin is JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. SwiftJLI requires Swift tools 6.2 or later, Swift 6 language mode and Apple deployment floors of 26.0. Raise the application's floor in its separately assigned cutover. No stable 1.1.0 release is implied: use an explicitly reviewed revision for trials.

## API mappings

| JLISwift | SwiftJLI |
| --- | --- |
| `JLIImage` containing packed `[UInt8]` | `ImageDescriptor` plus owning, sealed `Image` storage |
| `JLIEncoder().encode(_:configuration:)` | `try Encoder(configuration:)`, then `try await encode(_:options:)`; compressed bytes are `EncodedImage.data` |
| `JLIDecoder().decode(from:configuration:)` | `try Decoder(configuration:)`, then `try await decode(_:options:)`; samples are in `DecodedImage.image` |
| Decoder-owned result array | `decode(_:into:options:)` writes into a caller's `ImageDestination` |
| `inspect(data:)` | `inspect(_:options:)`, returning `ImageInfo` |
| `JLIError` | `CodecError.category`; task cancellation remains `CancellationError` |
| Mutable per-call codec configuration | Immutable encoder/decoder configuration, with per-call resource/execution/copy options |

Use module-qualified names when importing several suite libraries. Their types are independent; no shared runtime package or sibling checkout is required. `JLIDICOM` and `JLIBench` remain deferred products, not dependencies of SwiftJLI. DICOM parsing, windowing and transfer-syntax policy belong in consumers. Their disposition and fixture obligations are recorded in [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Current fidelity and layouts

The predecessor defaults to lossy quality 90/4:2:0; SwiftJLI defaults to true lossless SOF3 with point transform zero. The output size and format are therefore not equivalent defaults. `CodecOptions(predictor:restartInterval:)` selects predictors 1–7 and a restart interval in pixels for predictive JPEG, requiring complete rows (DCT uses MCU counts). For `.nearLossless(maximumAbsoluteError:)`, a positive integer bound selects the largest legal point-transform bound no greater than the request. Reports state the effective bound, which can be smaller (for example, a requested maximum of 2 selects an actual bound of 1). Lossy DCT requires explicit `.lossy` mode; `CodecOptions.dct` controls quality/distance, chroma sampling, sequential/progressive scan script, Huffman optimisation, trellis quantisation and perceptual tables.

Meaningful precision is explicit: 2–16 integer bits, stored in 8- or 16-bit unsigned words. Declaring `.uint16` in the predecessor could default to 12-bit precision; do not infer the new meaningfulBits from storage width or observed values. Samples exceeding their declared precision are rejected.

The shared path supports interleaved greyscale or RGB, little-endian words, prefix offsets and padded rows. Both caller-storage and allocating decode use the same final writer. Unsupported endian/layout conversions fail even with allowCopy at this checkpoint. Signed samples, floating point, alpha, YCbCr/CMYK and unrecognised colour interpretation are not silently converted.

ICC is `ImageDescriptor.iccProfile`; Exif TIFF bytes are `ImageMetadata.entries["Exif"]` (without the JPEG Exif identifier). Unknown preservation requirements fail. ICC interpretation is retained even under discardAncillary. Inspect reports decoded layout and metadata but does not certify the entropy stream.

## Explicit lossy trial

```swift
let configuration = try SwiftJLI.EncoderConfiguration(
    mode: .lossy,
    codecOptions: .init(dct: .init(quality: 90, chromaSubsampling: .yuv420,
                                  progressiveMode: .successiveApproximation)))
let encoder = try SwiftJLI.Encoder(configuration: configuration)
let result = try await encoder.encode(image)
```

DCT input is unsigned 8-bit storage/precision or 16-bit storage with exactly 12 meaningful bits; greyscale and RGB are supported. Quality is finite 0–100 (native table scaling clamps zero to quality 1); optional distance is finite 0–25 and takes precedence over quality. DCT-specific settings on a predictive configuration, or a nondefault predictive selector on a lossy configuration, are rejected. Decoding selects precision and scan behaviour from the stream; the output fidelity is `.lossy`.

`.scalarCPU` and `.required(.scalarCPU)` select the scalar kernels on every platform. Automatic DCT uses Accelerate on Apple and scalar elsewhere; required acceleration fails when unavailable. SOF3 remains scalar. Reports identify the selected backend and preferred-backend fallback. Availability lists are unions across profiles: DCT does not support the entire 2–16-bit predictive range.

Progressive DC scans currently require all components in frame order, with single-component AC scans. Multiple sequential scans, changing quantisation/restart definitions between scans, XYB and ambiguous RGB/CMYK JPEG interpretations are rejected. These restrictions are additional acceptance work, not silent conversions.

## Executable trial

[Examples/IndependentConsumer](Examples/IndependentConsumer) encodes real lossless JPEG, inspects precision, and verifies both allocating and caller-storage decode through the public API. It needs only this package:

```sh
swift run --package-path Examples/IndependentConsumer
```

Set realistic ResourceLimits for compressed bytes, samples, metadata and workspace. The predictive algorithm uses full-frame Int32 working planes and DCT uses Float/coefficient workspace; required sharing eliminates a hand-off copy, not that workspace. Conservative admission reservations and unmeasured peak fields are documented in the migration status. A preflight failure leaves an unwritten destination usable; failure after writing begins invalidates it.

## Application acceptance

1. Record exact old/new revisions, deployment targets, toolchains, modes, metadata and optional products. Preserve the application's existing fixtures and baseline failures.
2. Run the independent consumer and application tests, then compare both codec versions with independent oracles for each required mode and precision. Qualify lossy modes separately.
3. Verify padded storage, copy/allocation identity, malformed input, budgets, cancellation, concurrency and lifetime on the required platforms. Unknown report measurements do not mean zero.
4. Enable only qualified profiles behind the application's rollback mechanism. Keep the old dependency lock and adapter until persisted-file compatibility and platform acceptance are complete.

The diagnostic `swiftjli-cli` reports actual library capabilities. Its encode/decode/inspect/validate payload verbs remain unavailable under the separately budgeted CLI work. This guide does not announce a completed migration, stable release or complete platform support.
