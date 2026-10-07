# Codec migration status — 7 October 2026

Migration remains in progress. This checkpoint does not establish first-stable readiness.

Source: JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Successor base: `41b3cbc34e5e96db41853c925ec720fad4120b65`. Common suite policy: 0.10.0; shared contract documents are unchanged. Per-file origins and original hashes are in [provenance.json](provenance.json).

## Implemented checkpoint

The public Encoder/Decoder use the migrated native SOF3 kernel for unsigned 2–16-bit greyscale and explicit RGB. Lossless encoding fixes point transform to zero. Predictor 1–7 and row-aligned restart intervals are explicit controls. Packed little-endian 8/16-bit samples, padded rows and prefix offsets are supported. Other layouts currently fail even with allowCopy; no hidden repack is performed. Signed/float/alpha requirements are rejected.

Encoding borrows sealed source storage. Both decode call shapes use the same direct destination writer; a supplied destination incurs no second final image. Native Int32 planes/residuals remain algorithm workspace (8 bytes/sample on encode, 4 on decode, plus entropy, tables and compressed storage). Admission currently reserves conservative additional overhead: encode 64 bytes/sample + 4×metadata + 1 MiB, decode 8 bytes/sample + 64×compressed input + 1 MiB. These are admission bounds, not measured peak figures. Peak workspace reports remain unknown pending allocator measurement. Tight budgets can reject operations below their actual peak.

Each public lossless operation executes serially within its task, satisfying the worker ceiling without detached work. Row checks and bounded entropy-loop checks preserve cancellation/deadline errors. The native parallel implementations remain internal and covered by predecessor regression tests; public parallel lossless dispatch is not yet qualified.

ICC colour interpretation is retained, including under discardAncillary. Exif maps to ImageMetadata.entries["Exif"]. Unknown required metadata, unsupported marker semantics and incompatible destinations fail explicitly. Structural inspection does not certify entropy validity.

## Executed evidence

- Predecessor CI [35524297254](https://github.com/raster-labs/JLISwift/actions/runs/35524297254): succeeded at the pinned baseline.
- Successor pre-migration CI [37630552591](https://github.com/raster-labs/SwiftJLI/actions/runs/37630552591): all seven jobs passed, clearing the source-move prerequisite. This is baseline evidence, not migrated-code qualification.
- Linux ARM64, `swift:6.4-noble` digest `sha256:31d14d727f4451f25e29bac9c42563a098c39ac66415e8bad970f48038e38aca`: `swift test --scratch-path .build-linux -j 4` passed 212 tests in 22 suites. The test count does not count each parameter case separately.
- Local macOS ARM64/Swift 6.4: `swift build --disable-sandbox` passed. Local tests cannot load the CommandLineTools TestingMacros plug-in; macOS test/sanitizer qualification is delegated to CI.
- Diagnostic CLI: `Scripts/test-cli.py` passed 107 process checks, including real capability JSON, reserved verbs, streams and manual installation.
- libjpeg-turbo 3.2.0 (20260630): 105 cases (precisions 2–16 × predictors 1–7, two-row restart interval) passed in both directions. Its djpeg decoded SwiftJLI output sample-exactly, and the public decoder decoded independent cjpeg output sample-exactly. These are generated synthetic samples, with no patient data or external fixtures.

Reproduce independent interoperability from the repository root:

```sh
python3 Scripts/verify-lossless-interop.py --output-dir /tmp/swiftjli-oracle --scratch-path /tmp/swiftjli-oracle-build
```

The script requires installed lossless-capable cjpeg/djpeg and a compatible Swift toolchain. These are development-only oracles, never runtime fallbacks. Embedded predecessor oracle fixtures remain in the native regression tests with their original provenance comments.

## Remaining migration requirements

- Public baseline/extended/progressive lossy mode controls and shared-storage integration; honest per-operation capabilities, colour and float semantics.
- Fully portable selectable scalar/accelerated backends; Apple DSP comparisons and exact rounding qualification.
- Adapt the predecessor contract-layer, regression/conformance corpus and benchmark identity fixtures still outside this checkpoint. Deferred JLIBench does not defer its fixtures.
- Complete parser/entropy security review, mutation/resource/cancellation tests, fuzzing, sanitizers and native platform/SDK coverage.
- Measure memory/copy instrumentation and release performance against the pinned predecessor; qualify the shared-storage cross-codec extension.
- Finish documentation, independent versioned consumption and the full acceptance audit. CLI payload verbs remain separately budgeted new work under IMPLEMENTATION.md I3; diagnostic capabilities already read the real library values.

No predecessor release, consumer cutover, archive, stable successor tag or merge has been performed by this checkpoint.
