# Qualification checkpoint

Shipping source is `aa6e298cd89aadd37b27d69e9c8c957f39c3d409`; this checkpoint adds
development integration and validation evidence. See [the acceptance ledger](../ACCEPTANCE.md)
for remaining gates. `results.json` binds source, harness and evidence hashes.

Executed with exit 0:

- A fresh URL-based consumer pinned to the shipping SHA, using Apple Swift 6.4.
- macOS and Linux ARM64 diagnostic CLI, each with 107 process/install/manual checks.
- SwiftJ2K ↔ SwiftJLI integration in both directions, six cases with two concurrent
  readers each; independent libjpeg-turbo 3.2.0 and OpenJPEG 2.5.4 decode all 12
  final outputs sample-exactly. Separate macOS ASan and TSan executables pass.
- Linux/glibc allocation calibration, 12 integrated measurements and 12 deliberate
  full-destination-copy controls. `verify-cross-codec-heap.py` requires one versus
  two destination-sized allocations. This includes allocation, decode and both
  reader encodes, but excludes pre-existing seed creation and oracle processes.
- Linux `strace -f -e trace=open,openat,openat2,creat,memfd_create,execve`: one initial
  executable and 12 write opens, all named final JPEG/J2K outputs. No intermediate
  decoded image file or external codec process is observed.
- Actual SHA-256 contents of 28 common documents match across the four recorded
  repository revisions; predecessor provenance verification passes.
- CI [37752829169](https://github.com/raster-labs/SwiftJLI/actions/runs/37752829169)
  succeeds after retrying the macOS runner-capacity failure.

Reproduction commands for cross-codec operation, oracles and allocator controls
are in [the example README](../../../Examples/CrossCodecIntegration/README.md).
The native/sanitizer logs retain compiler commands and exact paths. Linux uses
`swift:6.4-noble` (digest
`sha256:31d14d727f4451f25e29bac9c42563a098c39ac66415e8bad970f48038e38aca`).
For sanitizer runs use distinct scratch directories and `--sanitize address` or
`--sanitize thread`. The Linux interposer is excluded from Apple builds.

The minimised Docker image's `/usr/bin/man` is a message-only stub. Installing
man-db places the real executable at `/usr/bin/man.REAL`; exposing that executable
through `/usr/local/bin/man` fixes the qualification environment. The CLI/manual
installer itself required no change. The failed stub-based check was not counted
as a pass.

Swift Build generated the unmodified `spdx-raw.json` and `cyclonedx-raw.json` with
`swift build --build-system swiftbuild -c release --product SwiftJLI --sbom-spec
spdx|cyclonedx --sbom-filter all`. Its missing bundled schemas triggered independent
validation with jsonschema 4.25.1 against the official
[SPDX 3.0.1 schema](https://spdx.org/schema/3.0.1/spdx-json-schema.json) and
[CycloneDX 1.7 schema](https://github.com/CycloneDX/specification/blob/master/schema/bom-1.7.schema.json).
Schema source revisions and hashes are retained. CycloneDX passes. SPDX fails on
two generated package records with unrecognised `externalUrl` and
`software_internalVersion` properties; no field was deleted to force a pass.
The general validator also cannot enumerate local Swift Testing tests with this
Command Line Tools installation, because its TestingMacros plug-in is missing.
Full macOS suite results come from Xcode CI, not that failed local invocation.
