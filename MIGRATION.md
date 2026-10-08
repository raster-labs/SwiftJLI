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

The shared path supports interleaved greyscale or RGB, little-endian words, prefix offsets and padded rows. Both caller-storage and allocating decode use the same final writer. Unsupported endian/layout conversions fail even with allowCopy at this checkpoint. Signed samples, CMYK and unrecognised colour interpretation are rejected. DCT RGBA and preconverted YCbCr require the explicit policies described below. Float input requires the explicit policy below. An explicit greyscale Float32 decode profile is described below.

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

DCT input is unsigned 8-bit storage/precision or 16-bit storage with exactly 12 meaningful bits; greyscale and RGB are supported. Quality is finite 0–100 (native table scaling clamps zero to quality 1); optional distance is finite and nonnegative and takes precedence over quality. Large distances saturate quantisation steps within the JPEG table range before integer conversion; they do not require an arbitrary upper limit of 25. DCT-specific settings on a predictive configuration, or a nondefault predictive selector on a lossy configuration, are rejected. Decoding selects precision and scan behaviour from the stream; the output fidelity is `.lossy`.

`.scalarCPU` and `.required(.scalarCPU)` select the scalar kernels on every platform. Automatic DCT uses Accelerate on Apple and scalar elsewhere; required acceleration fails when unavailable. SOF3 remains scalar. Reports identify the selected backend and preferred-backend fallback. Availability lists are unions across profiles: DCT does not support the entire 2–16-bit predictive range.

Progressive DC scans currently require all components in frame order, with single-component AC scans. Multiple sequential scans, changing quantisation/restart definitions between scans and ambiguous RGB/CMYK JPEG interpretations are rejected. The recognised XYB profile has an explicit colour policy described below. The remaining restrictions are additional acceptance work, not silent conversions.

## Decoder output and adaptive profiles

`Decoder.inspectJPEG(_:options:)` is the JPEG-specific extension for predecessor `JLIJPEGInfo` users. It returns common `imageInfo` plus encoded coding process, progressive/extended-precision flags, recognised XYB, relative chroma sampling, exact component sampling factors, scan count and restart interval. Predictive streams also expose predictor and point transform; nonzero point transform is not exact lossless fidelity. This extension is necessary because the common full-resolution descriptor cannot represent compressed scan/sampling structure (COMMON_API API-13). It uses the same bounded parser and errors as `inspect`, without a pixel decode. Neither inspection call certifies entropy validity, and decoder output scale/format does not alter encoded inspection geometry.

```swift
let details = try SwiftJLI.Decoder().inspectJPEG(jpegData)
print(details.codingProcess, details.chromaSubsampling, details.bitsPerComponent)
```

Signed-labelled predecessor input deserves separate review: its SOF3 encoder preserves the bit patterns, but its decoder does not restore `isSigned`. The successor's standalone JPEG path rejects signed descriptors as COMMON_API API-06 requires. A caller needing signed interpretation must qualify an explicit external-metadata contract; a RAM flag or a private JPEG marker would not establish that contract.

`DecoderConfiguration(scale:)` accepts 1, 2, 4 or 8. DCT output dimensions are `ceil(encodedDimension / scale)`; the existing native DCT reduction is used directly. Predictive JPEG requires scale 1. `inspect` always describes encoded geometry/precision, even on a decoder configured for reduced output. Resource admission still includes the full coefficient workspace.

`DecoderConfiguration(scale: 2, sampleFormat: .float32RawSamples)` explicitly returns raw reconstructed sample values as little-endian IEEE Float32, without integer rounding or normalisation. For example, a reconstructed 12-bit sample near 2048 remains near 2048, not 0.5. This profile supports greyscale DCT JPEG without ICC interpretation; colour, ICC-bearing input and SOF3 are rejected before the destination borrow. The result descriptor is `.floatingPoint` with 32 storage/meaningful bits. Supplied destinations must declare that same interpretation; default integer decode does not infer a float conversion from the destination.

The Float32 restriction avoids attaching a nominal integer-range ICC profile to differently represented samples without a qualified range/colour policy. Broader ICC and independent interoperability qualification remain migration work. Capabilities describe the queried operation and include Float32 profiles. Their precision range is nil because integer 2–16 and IEEE Float32 are separate profiles rather than one continuous range.

`DCTOptions(adaptiveQuantisationField: true)` enables the luma-derived trellis-strength field. It requires `adaptiveQuantisation: true`. `DCTOptions(jpegliAdaptiveQuantisation: true)` instead selects the masking/zero-bias path. These field options require 8-bit input and cannot be combined; unsuitable combinations fail rather than silently selecting a different quantiser. Both preserve direct source reads and use accounted algorithm workspace.

### Explicit normalised Float32 encoding

`DCTOptions(floatInputPolicy: .normalisedClampedToUInt8)` with `mode: .lossy` enables little-endian Float32 greyscale/RGB input. Each finite value is clamped to [0,1], multiplied by 255, and rounded to nearest with ties away from zero, matching the predecessor's finite Float32 input mapping. NaN and infinity fail with `invalidArgument`. The default policy rejects float input; selecting this policy for integer storage also fails. It cannot enable float lossless encoding.

Quantisation is fused into the scoped source reader. Padded rows and prefix offsets are honoured without materialising an intermediate UInt8 image. The result reports `.lossy` fidelity and `sampleConversion == .normalisedFloat32ClampedToUInt8`; `copyEvents` continues to describe actual memory copies. The output JPEG has 8-bit precision. ICC/Exif are retained under the existing metadata policy. This explicit normalised input policy differs from raw sample-unit Float32 decode; callers must not feed raw decode values back as normalised input without their own deliberate mapping.

### Explicit XYB colour encoding and decoded interpretation

`DCTOptions(chromaSubsampling: .yuv444, colourSpace: .xybFromSRGB)` with explicit lossy mode enables the retained XYB encoder. Input must be RGB8, or normalised RGB Float32 with the explicit quantisation policy above. Selecting this mode asserts sRGB interpretation. An absent source ICC or the exact sRGB2014 profile emitted by this decoder is accepted; other source profiles reject rather than being silently reinterpreted. XYB requires sequential 4:4:4, perceptual tables and zero restart interval. Trellis and its adaptive field remain selectable; the unrelated jpegli zero-bias field is rejected. These restrictions expose the predecessor's actual supported path instead of ignoring options.

The JPEG contains the retained XYB ICC profile and Adobe transform 0. Inspection reports original X/Y/B component roles, unknown generic colour interpretation and the embedded profile. Decode recognises that exact profile/transform combination, writes sRGB integer samples directly into final caller storage, and attaches the unchanged ICC sRGB2014 profile. `OperationReport.colourConversion` records `.sRGBToXYB` or `.xybToSRGB`. Scaling 1/2/4/8 is supported. `DecoderConfiguration(sampleFormat: .float32NormalisedSRGB)` returns the fractional XYB inverse divided by 255, before integer rounding, with the same sRGB profile and `.rawSRGBToNormalisedFloat32` sample-conversion report. Unlike the predecessor's raw 0–255 float RGB buffer, these explicitly selected samples use the normalised 0–1 range expected by the profile. The greyscale `.float32RawSamples` policy remains separate; it does not accept XYB. Other JPEG colour interpretations cannot silently acquire sRGB normalisation. Supplying a destination with the original XYB profile is incompatible with the converted sRGB result.

The profile's [source and licence](Documentation/Migration/Fixtures/ICC-LICENSE.txt) and exact byte hash are recorded; provenance verification checks the embedded bytes. No runtime colour-management service or external codec is required. ColourSync is used only as an independent test oracle.

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

## Explicit DCT input conversions

`DCTOptions(alphaPolicy: .discardStraightAlpha)` permits interleaved RGB plus straight alpha at UInt8, UInt12-in-UInt16 or opted-in normalised Float32 precision. The descriptor must use `[.red, .green, .blue, .alpha]`, `.rgb` and `.straight`. Alpha is discarded without compositing; premultiplied alpha is rejected. `OperationReport.alphaDiscarded` records the loss. The default still rejects RGBA. Every actual Float32 component, including discarded alpha, must be finite; padding is not interpreted as samples.

`DCTOptions(sourceColourSpace: .yCbCr)` permits full-range JPEG Y/Cb/Cr input at UInt8 or opted-in normalised Float32 precision. Use `[.uninterpreted("Y"), .uninterpreted("Cb"), .uninterpreted("Cr")]`, `.unknown` generic colour, absent alpha and no ICC profile. UInt8 chroma is centred at 128; Float32 uses the same explicit clamped 0–1 to UInt8 mapping. Components feed the codec planes directly without a second RGB-to-YCbCr transform. Twelve-bit preconverted YCbCr, XYB conversion and greyscale conversion from this profile reject.

`DCTOptions(chromaSubsampling: .greyscale)` explicitly converts RGB8 or opted-in normalised Float32 RGB to one luma component. It can combine with straight-alpha discard for RGBA. The report records `.rgbToGreyscale`; no RGB ICC profile is copied onto greyscale output. ICC-bearing colour input and UInt12 RGB-to-greyscale currently reject because their conversion semantics are unqualified. The existing greyscale input path remains available at 8/12 bits.

These options require `.lossy`. All three paths borrow source storage, honour prefix offsets/padded rows and use bounded colour-row scratch plus algorithm planes. There is no packed intermediate image. [118 public comparisons](Documentation/Migration/ColourInput/results.json) against the actual pinned predecessor match codestreams and decoded samples; the retained Linux matrix also checks scalar operation, padding and explicit rejection. Allocation reports are source-path assertions, not new independent encoder allocator measurements.

## Bounded codec workers

`ResourceLimits.maximumWorkers` now bounds joined parallel predictive encoding, DCT trellis/AC counting, chroma interpolation and full-resolution reconstruction. One remains a supported deterministic serial policy. Workers receive the selected backend, deadline and operation cancellation token explicitly; all lanes join before any borrowed storage is released or an error is returned. Cancellation checks cover bounded sample/block units and final publication. Progress callbacks stay on the invoking task. Other public stages remain serial; a worker cap is a ceiling, not a promise to parallelise every stage. The default ceiling is at most eight CPUs (two for the Watch profile).

RGB8 output conversion also uses bounded joined workers. Each owns at most eight rows of colour scratch; accelerated conversion uses contiguous byte planes and interleaves directly into the final destination with its actual row stride. The scratch is algorithm workspace and is covered by conservative resource admission. [RGB output evidence](Documentation/Migration/RGBOutput/README.md) records padding, race/sanitizer and performance checks, including unresolved smaller-case regressions.
