# Four-codec shared-storage qualification

This development-only package exercises every ordered pair among SwiftJLI,
SwiftJ2K (`be4e7a3`), SwiftJLS (`f481f60`) and SwiftJXL (`2534240`). Full
immutable revisions are in Package.swift. Shipping library dependencies are
unchanged. The common profiles are unsigned greyscale lossless JPEG, Part 1
JPEG 2000, JPEG-LS and Modular JPEG XL with 12/16 meaningful bits.

From the repository, using fresh output directories:

```sh
swift run --package-path Examples/SuitePairIntegration -c release SuitePairIntegration /new/outputs
python3 Scripts/verify-suite-outputs.py --input /new/outputs --output /new/oracles --oracle-image YOUR_ORACLE_IMAGE
```

The six image cases are 19×13, 65×31 and 257×17 at both precisions. All twelve
ordered directions must preserve every sample and produce identical compressed
bytes to an encode of the original source: 72 handoffs. Each uses different
source/destination strides, row padding, caller-owned destination identity, two
simultaneous reader encodes and rejection of mutation after sealing. Every
codec also checks callback cancellation of encode/decode, reuse of the same
destination after pre-write cancellation, and dimension mismatch rejection
under both copy policies. These are not claims of mid-kernel cancellation or a
successful layout-conversion fallback. Unsupported HTJ2K, signed interpretation,
multi-frame and reconstruction/coefficient transcoding are outside these common
capabilities.

The adapter retains each codec's sealed read-only owner and forwards scoped
reads; no raw pointer escapes and it creates no handoff pixel array. SwiftJXL
reports its allocation count as unknown (`nil`), which is preserved as unknown.
On ordinary Linux builds, independent HeapProbe telemetry covers destination
allocation, decode and both concurrent encodes. Run once normally and once with
`SWIFTJLI_COPY_CONTROL=1`, then verify:

```sh
python3 Scripts/verify-cross-codec-heap.py --suite --baseline normal.log --control copied.log
```

Keep stdout and stderr separate. Calibration and all 72 cases must show one
final-destination-sized allocation normally and exactly one extra with the
injected full-frame copy. This detects the tested allocation shape, not every
possible copy instruction. Algorithm workspace remains permitted and appears
in the raw size histograms. Run ASan and TSan separately without using their
allocation figures. Retained Linux file/process tracing requires exactly 72
final compressed writes and no external codec execution inside the harness.

Independent verification uses host lossless-capable libjpeg-turbo `djpeg` and
OpenJPEG `opj_decompress`, plus a network-disabled development container with
CharLS and libjxl `djxl`. Build Oracle/charls-pgm.cpp against CharLS in that
container. The recorded qualification used libjpeg-turbo 3.2.0, CharLS 2.4.2
and libjxl 0.7.0. All output headers must preserve original geometry and bit
depth. libjxl 0.7 writes normalised UInt16 PNM values for 12-bit input; its
float rounding may differ by one 16-bit unit. The verifier records that bound
and requires exact inversion to every original 12-bit integer. This is an
oracle representation conversion, not permission for codec sample loss.
Commands, tool output and input/output hashes are retained. Oracles run only
after compressed output publication and never become runtime dependencies.
