# Prepared-revision hosted CI — 4 November 2026

[Run 41781795793](https://github.com/raster-labs/SwiftJLI/actions/runs/41781795793)
completed successfully on its first attempt: **13 jobs passed, no failed or
skipped jobs**. The [terminal receipt](terminal-receipt.json),
[raw run metadata](workflow-run.json) and [job/step metadata](workflow-jobs.json)
retain the exact conclusions and times. The monitor performed no rerun,
cancellation or workflow dispatch.

The PR head is `7739dba554cabebcc25e3593af3feb6ba27f8489`. Actions tested temporary
PR merge `30707ab6a47697f6eba63073a65d3f3017308d7c`.
[Their complete Git trees match](source-tree-identity.json), both
`e0dfe084ceb3b603216002483cf428d0497c0b6e`; this is evidence for the prepared
source, not an assertion that a later evidence-only commit ran the matrix.
Suite policy remains 0.10.0 and Apple deployment minima remain 26.0.

The jobs cover four Linux architecture/compiler combinations (Swift 6.2/6.4,
ARM64/x86_64), native macOS ARM and Intel, iOS/tvOS/watchOS/visionOS simulators,
Apple SDK compilation, independent tools-6.2 consumption and shared-contract
byte identity. Native ARM Debug, Release, AddressSanitizer and ThreadSanitizer
steps passed. The workflow deliberately skips CLI checks in its two Swift 6.2
Linux jobs, Watch-only steps in tvOS/visionOS and failure diagnostics when their
preceding Release tests succeed. These are recorded conditional step skips,
not failed or skipped jobs; no zero-skip claim is made for the entire workflow.

## Watch proof

The [Watch job](https://github.com/raster-labs/SwiftJLI/actions/runs/41781795793/job/126414791888)
passes the 389-declaration Debug library suite, the six-case Release resource
and cancellation harness, and the strict simulator verifier. The retained
[library report](watch-proof/runtime/report.json) and
[harness report](watch-proof/watch-qualification/report.json) include exact
commands and numeric exit codes. The six Release tests and six unique
`watch-simulator` records have zero failures/skips in the
[xcresult summary](watch-proof/watch-qualification/verification/xcresult-summary.json).

The runner used Xcode 26.6 / 17F113, Apple Swift 6.3.3 and watchOS simulator
26.5 on arm64. The [hosted verifier receipt](watch-proof/watch-qualification/verification/receipt.json)
binds 49 source files to the current prepared tree, toolchain identity, test
command, six records and result bundles. The original 51-file xcresult remains
unchanged; its query copy adds only the permitted SQLite cache. Independent
read-only review replayed strict validation against the retained JSON and log
without executing tests or `xcresulttool` locally.

The original [Watch artefact ZIP](watchOS-runtime-evidence.zip) is retained with
its GitHub digest and download details in [watch-download.json](watch-download.json).
It preserves the original result bundle and the verifier's query copy.
[Selected proof files](watch-proof/) are exact extracted bytes; the
[archive manifest](archive-manifest.json) binds their hashes and the raw
metadata/log captures. Only this artefact and Watch job log were downloaded;
other jobs are accepted from terminal GitHub job/step metadata, not invented
local execution receipts. Actions supplies step conclusions, not arbitrary
numeric process exit codes for every job.

This is hosted software qualification. It does not establish physical Watch
memory ceilings, representative iPhone/iPad execution, DICOMKit successor
integration, stable-tag consumption or stable publication. Those requirements
remain in [the release-completion record](../README.md).
