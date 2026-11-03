# Structural parser reservation experiment

Candidate `ca0c1e874177f429ed199f3ed8ef6ac1315ee66a`, isolated from the C-row baseline `5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd`. Suite policy 0.10.0; Apple deployment floor 26.0, Swift 6.2 manifest minimum. This checkpoint ran locally with the Xcode toolchain recorded in the command receipts. It does not establish other platform or compiler support and is not an integration decision.

The parser previously reserved `64 × compressedBytes + 1 MiB`. This trial keeps the existing limits and uses the existing validation pass to count definitions and retained records:

```
inputCopies × compressedBytes + 1 MiB
+ 4096 × allHuffmanDefinitions + 1024 × allQuantiserDefinitions
+ 4096 × scans + 64 × (frameComponents + scanComponents)
+ 4 × allAcceptedAPPPayloadBytes
```

`inputCopies` is one for public Data and two for the internal array convenience. A checked bootstrap reservation precedes the immutable Foundation input bridge. The complete structural reservation is admitted before MarkerReader allocates expanded tables, then retained in the immutable parsed representation and added to the unchanged image workspace for decoding. Every table version is counted, including replacements. Metadata, malformed-input, cancellation and all independent resource ceilings remain enforced. This reservation is an admission bound, not allocator or RSS telemetry. No extra entropy traversal, decoded-image copy, output precision change or new unsafe concurrency operation was introduced.

## Executed gates

| Gate | Result |
| --- | --- |
| Focused parser, envelope, ownership and admission Release tests | 52 tests / 8 suites, exit 0 |
| Full Release tests | 468 tests / 79 suites, exit 0 |
| Native DCT baseline comparison | 12 fixtures × 2 balanced rounds, all full-output hashes and byte counts identical |
| Native lossless baseline comparison | 16 cases × 2 balanced rounds, all full outputs exactly equal to retained original source |
| Newly eligible default CLI cases | noise-2048, noise-3072 and mixed-3072: baseline exit 5, candidate exit 0; unchanged default ceilings |
| Independent new-case sample checks | Candidate and djpeg 3.2.1 each exactly match the entire original 16-bit sample buffers: six comparisons |

Every timed process uses five warmups and twenty individual measured decodes, with the duration captured before output release. The primary lossless Swift harness is byte-for-byte the previously used `c-row-composed/targeted-matrix.swift`; it traverses all sixteen cases per process. The DCT runner pairs each fixture and reverses version order in the second round. Identical explicit 8 GiB workspace / 10 GiB total budgets are used in native diagnostics. Those budgets are not used in the separate CLI admission checks. No 500-decode tiny timing was executed; the generic DCT harness has an unused batched lossless mode, while the actual primary lossless gate uses its separate original harness.

No case regressed by more than 5% in both rounds. Scattered one-round regressions and tiny-case variation are retained in `qualification.json`; these are provisional shared-host results and do not support a tiny-image speed claim. Snapshots record other host activity. Native benchmark summaries are not substituted for fresh-process CLI/RSS results.

The default-admission attempt 1 failed before decoding because the harness combined `--output-format pnm` with a `.pgm` suffix. Baseline CLI correctly rejected the argument conflict with exit 2; candidate was never invoked. That runner, receipt and logs are retained. Version 2 changes the output suffix to `.pnm`, records the initial failure and passes all three cases. Newly eligible cases are separate from the existing same-eligibility CLI benchmark, and are not counted as historical timing wins.

## Receipts and limits

`qualification.json` contains the aggregate, exact receipt hashes and per-round median deltas. `source.json` and `trial.patch` identify the implementation. Each runner records commands, exits, logs and immutable input hashes; native inputs include the compiler, Swift/C objects, module files, module map, actual umbrella header, fixtures and executables. All assertions passed and the source remained clean at the pinned revision. C source and Package.swift are byte-identical to baseline; aggregate C object hashes differ because the builds are in different directories and are recorded independently.

The new tests cover pre-bridge workspace/total/compressed boundary ordering, arithmetic overflow and negatives, every retained table version, 128 scan snapshots, 255 frame/scan components, maximum Exif/ICC chunk metadata, malformed quantisers, cancellation, exact noisy output, public provider no-borrow rejection and reservation carry. Existing ownership tests cover immutable input ownership, retained scans and concurrent readers. Resource admission is still conservative; no physical peak-memory reduction is asserted.

ASan, TSan, full CLI regression, fresh-process RSS and cross-platform/toolchain CI have not been executed for this candidate in this grant. The parent owns those remaining qualification and integration decisions. All binary executables, dSYM content and generated PNM images are excluded from the text inventory, with their exact original hashes retained separately in `index.json`.
