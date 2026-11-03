# Callback-owner performance qualification

**The controlled performance gate is still pending.** The completed
[loaded run](measured/results.json) has 24 rows with exact baseline/candidate
outputs, but its before/after snapshots show an unrelated SwiftJLS benchmark
at approximately 100% CPU plus substantial virtual-machine/Java activity.
The [separate disposition](loaded-disposition.json) excludes it from controlled
acceptance without changing the raw results. No djpeg speed claim is made here.

The loaded run also used a historical baseline built with testability enabled,
while the candidate used a product build. [Retained build settings](loaded-build-settings.json)
document that difference. Its two `progressiveRGB8-512` **encode** rows used
sequential encoding of pixels decoded from a progressive JPEG; those rows do
not measure progressive encoding. The input **decode** rows are progressive.

[run-loaded.py](run-loaded.py) preserves the executed loaded-run source exactly;
its SHA-256 matches the raw receipt. The earlier
[initial attempt](initial/results.json) stopped with CLI usage exit 2 before
timing because stdout JPEG encoding lacked `--output-format jpeg`. That receipt
retains the original command, diagnostic and runner hash. Its exact runner
bytes were not retained before the first correction. Neither receipt is a
successful controlled performance result.

The generated PNM intermediates are archived outside Git. Their original and
compressed hashes are in [the archive receipt](loaded-pnm-archive.json); the
runner regenerates them from the pinned JPEG fixtures and baseline executable.

## Prepared matched builds

[matched-builds.json](matched-builds.json) records fresh baseline
`8ae2762710d6279cd92222f5bb5ca95f042f694e` and candidate
`f548e5048e5c71204c2a2ec4036bf66c4f040285` source manifests, executable/compiler
hashes and exact build commands. Only `Sources/SwiftJLI/NativeExecution.swift`
differs in shipping source. Both builds use Apple Swift 6.4.2, the Swift Build
build system, Release, two jobs and the `swiftjli-cli` product. Their
[baseline](baseline-build-request.json) and
[candidate](candidate-build-request.json) XCBuild request parameters match
after excluding the distinct scratch arena paths. Both target ARM64 and the
MacOSX27.2 SDK; the package's deployment floor remains 26.0. Compiler invocation
arguments are not present in the retained XCBuild manifest and are not
reconstructed. Build duration is not used as a codec performance metric.

The [fixture provenance](fixture-provenance.json) pins the six synthetic JPEGs
and their retained generators. The original five fixtures descend from the
JLISwift benchmark generator at
`b6df774a3c3ecdf4b98971f31543fdd18074ace2`; `flat-19` comes from the retained
SwiftJLI pattern generator. These are existing fixtures; no fixture was
regenerated for this refinement.

## Future controlled run

Wait until the fuzz campaign, other codec benchmarks and substantial competing
workloads have completed. Do not terminate unrelated work to obtain a quiet
host. Run from the repository root, choosing an output directory that does not
already exist:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  Documentation/Migration/Qualification/Milestone5/performance/run.py \
  --baseline /private/tmp/swiftjli-m5-baseline-performance/out/Products/Release/swiftjli-cli \
  --candidate /private/tmp/swiftjli-m5-release-performance/out/Products/Release/swiftjli-cli \
  --fixtures /private/tmp/swiftjli-benchmark-20261102/BenchmarkResults/2026-11-02/memory \
  --patterns /private/tmp/swiftjli-native-matrix-fixtures \
  --build-metadata Documentation/Migration/Qualification/Milestone5/performance/matched-builds.json \
  --output Documentation/Migration/Qualification/Milestone5/performance/controlled
```

The maintained [runner](run.py) requires fresh output, validates binary and
candidate-source hashes against the supplied build receipt, validates fixture
hashes, and retains its executed source in the new output directory. Metadata
and fixture locations are anchored to the maintained script; the copied
executed source is an archive, not a separate reproduction entry point.
Sources, executables, fixtures and runner/helper/metadata hashes must remain
unchanged through the run. A rebuild needs a new audited build receipt.

The progressive case now explicitly encodes with
`--progressive successive-approximation`; other lossy encodes use sequential
mode and all use quality 85. This changes the workload relative to the loaded
run, so a future progressive encode row must not be combined with its old
sequential row. Baseline/candidate outputs must match byte for byte before
timing each round. Independent oracle qualification and the historical RGB
djpeg tolerance-2 timing exclusions remain separate and unchanged.

Each operation uses five warmups, twenty fresh-process measurements and two
rounds, alternating which binary runs first on each iteration and reversing
the first order across rounds. Median, nearest-rank p95 (sample 19 of 20),
minimum, maximum and all raw samples are retained. Pixel throughput is image
pixels divided by median elapsed seconds. Wall time includes Python process
launch/wait, `/usr/bin/time -l`, input reads, codec work and output to
`/dev/null`. Peak RSS is whole-process memory, not codec workspace or a count
of callback-owner allocations. Small-operation kernel cost cannot be isolated
by these timings. Environmental snapshots require review; a completed runner
does not automatically establish a controlled host or close the gate.

The script refinement is checked without running a codec or benchmark; see
[refinement-checks.json](refinement-checks.json). No source or test implementation
was changed by this performance evidence refinement.
