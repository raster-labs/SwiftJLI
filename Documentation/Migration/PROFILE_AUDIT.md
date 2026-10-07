# Predecessor public-profile audit

Source baseline: JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Initial successor checkpoint: `197b20913473855d8828a82a50891ce6f2fae504`; the tables below include subsequent implementations. This is a public-surface disposition audit, not a claim that every input combination has been qualified. The initial audit was read-only; subsequent implementations and evidence are identified below. The [executed five-case comparison](ProfileAudit/results.json) supplements the source inspection; it uses public APIs from both packages and records exact source hashes.

## Encoder configuration

All 16 stored fields of the predecessor's [JLIEncoderConfiguration](https://github.com/raster-labs/JLISwift/blob/0a4ded0b0b2e8e38127f4f302b286e74ee352474/Sources/JLISwift/Core/JLIConfiguration.swift) are accounted for below. Mapped means an explicit successor control exists; it does not imply identical validation/defaults or complete cross-product coverage.

| Predecessor control | Successor disposition |
| --- | --- |
| `quality` | `DCTOptions.quality`; finite 0–100 |
| `distance` | `DCTOptions.distance`; every finite nonnegative value, with safe quantisation saturation. See DistanceRange evidence below. |
| `chromaSubsampling` | `.yuv444`, `.yuv422`, `.yuv420` mapped. Greyscale input remains one component. Explicit `.greyscale` maps supported RGB-to-luma profiles; precision/ICC restrictions are documented in MIGRATION.md. |
| `colorSpace` | `.yCbCr` and explicit `.xybFromSRGB`; XYB asserts input interpretation and rejects unqualified combinations instead of ignoring options. |
| `progressive` | Combined into `.sequential` versus progressive scan selection. |
| `progressiveMode` | `.spectralSelection` and `.successiveApproximation` mapped. |
| `restartInterval` | `CodecOptions.restartInterval`; predictive row-alignment and DCT MCU semantics are documented. |
| `lossless` | Explicit `.lossless`, now the default; DCT requires `.lossy`. |
| `losslessPredictor` | `CodecOptions.predictor`, 1–7. |
| `losslessPrecision` | `ImageDescriptor.meaningfulBits`, 2–16; zero/inferred precision is deliberately removed. |
| `losslessPointTransform` | `.nearLossless(maximumAbsoluteError:)`; report gives the effective `2^Pt−1` bound. |
| `optimiseHuffman` | `DCTOptions.optimiseHuffman`; native precision restrictions remain. |
| `adaptiveQuantization` | `DCTOptions.adaptiveQuantisation`. |
| `adaptiveQuantField` | `DCTOptions.adaptiveQuantisationField`; explicit compatible 8-bit profile. |
| `perceptualQuantTables` | `DCTOptions.perceptualQuantisationTables`. |
| `jpegliAdaptiveQuant` | `DCTOptions.jpegliAdaptiveQuantisation`; explicit compatible 8-bit profile. |

Computed `isNumericallyLossless`/`isLossy` correspond to explicit configuration modes and effective operation fidelity. The predecessor's `.diagnosticLossless` intent maps to the successor's default exact mode, but no medical qualification is implied. Options the predecessor ignored in a selected mode may now reject; callers must remove irrelevant settings rather than assume the entire old configuration object can be copied.

## Sample and colour profiles

The predecessor image type declares UInt8, UInt16 and Float32 storage plus six colour model labels. Actual encoder branches, not enum availability, determine support: see [JLIEncoder](https://github.com/raster-labs/JLISwift/blob/0a4ded0b0b2e8e38127f4f302b286e74ee352474/Sources/JLISwift/Encoder/JLIEncoder.swift).

| Profile | Current evidence/disposition |
| --- | --- |
| Unsigned greyscale/RGB predictive 2–16 bits | Public successor path and exact native/oracle comparisons exist. |
| Unsigned greyscale/RGB DCT 8/12 bits | Public sequential/progressive path; borrowed-storage, native identity and independent JPEG comparisons exist. |
| Normalised Float32 input | Explicit finite clamping/UInt8 quantisation policy; native/public codestream comparisons exist. No implicit float-lossless claim. |
| RGB-to-XYB encoding | Explicit sRGB policy, integer/normalised Float32 input, native byte identity and independent profile tests. |
| RGBA DCT input | Explicit `.discardStraightAlpha` supports RGBA UInt8/UInt12 and opted-in Float32. Public predecessor comparisons include sequential/progressive and XYB profiles; the report records alpha removal. Premultiplied alpha rejects. |
| Preconverted YCbCr8 input | Explicit `.yCbCr` source policy supports UInt8/opted-in Float32 with named Y/Cb/Cr roles and no ICC. Public predecessor comparisons match. Twelve-bit input remains rejected, as in the predecessor. |
| RGB8 → greyscale (`yuv400`) | Explicit `.greyscale` supports RGB/RGBA UInt8 or opted-in Float32 without ICC. Public predecessor comparisons match and `.rgbToGreyscale` reports the conversion. UInt12 and ICC-bearing colour conversion remain unqualified and reject. |
| Signed integer bit patterns | **Contract-required rejection.** The predecessor accepts signed-labelled UInt16 with full-precision predictive encoding and reproduces the bytes, but the executed decoded `isSigned` flag is **false**. Its image comment claiming propagated signed provenance is not borne out by code/runtime. The successor rejects signed descriptors. Do not restore the misleading provenance claim or silently reinterpret signed values as unsigned. |
| CMYK / already-XYB colour labels | An image enum case is not a working ordinary DCT encoder path. The predecessor's default colour-path guard rejects these labels; they are not evidence that the successor must claim CMYK or arbitrary raw XYB support. Special combinations need their own audit before any support claim. |
| ICC/Exif | Explicit descriptor ICC and Exif metadata mapping exists. XYB output replaces the encoded XYB profile with matching sRGB. Arbitrary profile/range transformations remain unqualified. |

The initial three executed rejection cases required `unsupportedFeature`, not just any thrown error. Their source arrays and checks are retained in `ProfileAudit/Comparison.swift`.

## Decoder and inspection

| Predecessor control/information | Successor disposition |
| --- | --- |
| `scale` | 1/2/4/8 DCT reduction; predictive requires 1. Encoded geometry remains visible to inspection. |
| `outputPixelFormat == nil` | Native integer precision is preserved. Explicit integer widening/narrowing is not implied. |
| `.float32`, greyscale | Explicit raw-sample Float32, currently without ICC interpretation; native fractional samples are compared. ICC-bearing raw-float cases remain a restriction. |
| `.float32`, XYB | Explicit normalised sRGB Float32; mapping from predecessor raw 0–255 samples to 0–1 is deliberate and reported. |
| `.float32`, YCbCr colour / SOF3 | The predecessor rejects these paths too; enum presence is not evidence of support. |
| `outputColorModel` | The executed `.yCbCr` override relabels decoded RGB bytes without transforming them. The successor intentionally has no unqualified relabelling control. Correct colour conversion would be separate explicit behaviour. |
| Inspect width/height/component count/precision | Available through `ImageInfo.descriptor`. Extended integer precision can be derived from meaningful bits. |
| Inspect `isProgressive`, `chromaSubsampling` | `Decoder.inspectJPEG` exposes coding process, sampling classification and exact component factors. Common `ImageInfo` remains generic. |
| Inspect `isXYB` | `JPEGInspection.isXYB` reports the validated profile; original roles and ICC remain visible. |

See [predecessor JLIJPEGInfo](https://github.com/raster-labs/JLISwift/blob/0a4ded0b0b2e8e38127f4f302b286e74ee352474/Sources/JLISwift/Core/JLIJPEGInfo.swift), [decoder implementation](https://github.com/raster-labs/JLISwift/blob/0a4ded0b0b2e8e38127f4f302b286e74ee352474/Sources/JLISwift/Decoder/JLIDecoder.swift), and successor [CodecAPI](../../Sources/SwiftJLI/CodecAPI.swift)/[JPEGCodec](../../Sources/SwiftJLI/JPEGCodec.swift).

## Remaining public surface

`JLIEncoder`/`JLIDecoder` map to common `Encoder`/`Decoder`; the older duplicate contract layer has the deliberate disposition in IMPLEMENTATION.md/provenance. `JLIError` cases map to defined `CodecError` categories, rather than preserving source-compatible case names. `JLIPlatformCapabilities` becomes per-operation codec capabilities/backend reporting; architecture flags are not codec support claims. The predecessor namespace version constant is historical; the successor uses its package/CLI version record. `JLIDICOM` and `JLIBench` are explicitly non-shipping under IMPLEMENTATION I1/I2, with required helpers/fixtures retained for tests. CLI payload verbs remain new work under I3.

This audit makes the remaining differences concrete. It does not authorise waiving functioning predecessor profiles, claim that enum mappings equal qualification, or close platform, resource, performance and release gates.

## Subsequent inspection implementation and signedness disposition

`Decoder.inspectJPEG` now supplies the specialised inspection fields through one bounded parse, with the common `ImageInfo` included. Tests cover 8/12-bit sequential/progressive sampling, encoded geometry despite output configuration, exact factors for 4:4:0, recognised XYB, predictive point transform and resource/malformed-input failures. The predecessor's `MarkerReader.readInfo` hard-codes `isXYB: false`; the successor reports the validated profile instead of preserving that stub result.

The signed-input observation above is a contract-required rejection for plain standalone JPEG, not permission to add a private sign marker. COMMON_API API-06 requires an explicit external-metadata contract for unrepresentable signedness. Retaining an in-memory flag would not close that requirement. The migration guide now explains the predecessor's lost sign provenance and the successor's deliberate rejection. RGBA, preconverted YCbCr and RGB-to-greyscale now have explicit policies; see the qualification below.

The finite distance range gap is now closed: nonnegative finite distances are accepted, with quantisation saturated before integer conversion. [Executed comparisons](DistanceRange/results.json) at 26 and 1000 reproduce the pinned predecessor's codestreams and samples for 14 greyscale/colour, 8/12-bit, progressive, XYB and jpegli-AQ cases. Seven additional largest-finite-distance cases execute only the successor, avoiding the predecessor's unsafe conversion; they are robustness checks, not predecessor equality claims. Invalid negative/non-finite values still reject.

## Explicit colour input qualification

[ColourInput/results.json](ColourInput/results.json) records 118 public comparisons against the pinned predecessor on macOS ARM64: RGBA8/12/Float32, preconverted YCbCr8/Float32, RGB/RGBA-to-greyscale and RGBA-to-XYB, widths 1/19, applicable sampling and scan modes. Every codestream and decoded sample buffer matched. Source descriptors use padded rows and prefix offsets. Linux passes the 322-test suite, including alpha/padding independence, finite-float checks and rejected premultiplied/ICC/precision combinations. This closes the three missing public controls, not all performance, allocation or platform acceptance gates.
