# Structural parser reservation — 4 November 2026

**Locally qualified; the overall djpeg goal remains open.** Source `ca0c1e874177f429ed199f3ed8ef6ac1315ee66a` refines parser admission without raising any resource ceiling or changing decoded samples. The source was integrated as `0dc6730`, with byte-identical Sources, Tests and Package.swift. The previous C decoder is unchanged. The smaller FMA workspace, serial-C and joint experiments remain unselected.

## Behaviour and memory contract

The old reservation charged `64 × compressedBytes + 1 MiB`, including entropy bytes that remain shared ranges. The existing structural envelope pass now counts every Huffman and quantisation definition (including replacements), scan, frame/scan component and accepted APP payload. Admission occurs twice: a bootstrap gate before a possible Foundation input copy, then an expanded gate before table and metadata parsing. The immutable validated owner carries that reservation into final decode admission, which adds the unchanged image workspace before borrowing provider storage.

For public Data input, `P = B + 1,048,576 + 4096H + 1024Q + 4096S + 64(F + T) + 4A`, where B is compressed bytes, H/Q count all table definitions, S counts scans, F is frame components, T is the sum of scan component entries and A is accepted APP payload bytes. Bootstrap is `B + 1 MiB`. The internal array convenience conservatively retains `2B` in both reservations to cover Array-to-Data and possible bridge copies. Compressed input is also charged separately in total memory. Workspace, compressed, decoded, metadata and total ceilings remain independent and unchanged.

These are conservative allocation reservations, not measured RSS or `peakWorkspaceBytes`. The change admits ordinary large noisy inputs previously rejected by the overestimate. It does not reduce their actual decoded-image storage, and table-heavy inputs remain charged for every definition. Existing malformed-input, cancellation, ownership and metadata rules remain enforced.

## Validation

| Gate | Result | Evidence |
| --- | --- | --- |
| Focused Release | 52 tests / 8 suites; exit 0 | [Receipt](qualification/focused-release-1/command.json) |
| Full Release | 468 tests / 79 suites; exit 0 | [Receipt](qualification/full-release-1/command.json) |
| Focused ASan and TSan | 71 tests / 11 suites each; exit 0 | [Summary](qualification/safety/qualification.json) |
| C instrumentation | All three retained C units instrumented in both sanitiser builds | [Proof](qualification/safety/c-instrumentation.json) |
| CLI Release | 252 checks; exit 0 | [Receipt](qualification/safety/cli-1/command.json) |
| Native revision comparisons | 12 DCT cases and 16 lossless cases, two rounds; all outputs exact; no repeated regression over 5% | [Qualification](qualification/qualification.json) |
| Newly admitted default CLI cases | Three inputs; both Swift and djpeg 3.2.1 match all original UInt16 samples | [Oracle/admission receipt](qualification/default-cli-admission-2/receipt.json) |

[Parser reservation tests](../../../../../Tests/SwiftJLITests/ParserReservationTests.swift) cover exact/one-byte-short workspace and total bounds, compressed limits, overflow, progressive table snapshots, repeated quantisers, component/metadata maxima, input ownership, cancellation and destination reuse. [Streaming admission tests](../../../../../Tests/SwiftJLITests/StreamingWorkspaceAdmissionTests.swift) retain independent image payload checks. Synthetic fixture hashes and full-source equality checks are retained in the receipts; no patient images were added.

The first admission harness used a `.pgm` filename with explicit `pnm` format and correctly received usage exit 2 before candidate decoding. That [failed harness attempt](qualification/default-cli-admission-1/receipt.json) remains intact. The second version changes the suffix to `.pnm` and passes. This was not a codec correctness failure. Initial then-pending safety/integration wording in older receipts is historical; the later safety summary above closes the local gates.

## Newly admitted CLI timings

This is a separate comparison for inputs rejected by the old default admission. The frozen prior Swift binary must return resource exit 5; it has no accepted timing or speedup denominator. Both current Swift and djpeg must first match every original 16-bit sample. Five warmups, 20 subprocess measurements per engine, two balanced rounds, PNM to `/dev/null`. Wall time includes launch/input/decode/output and the same `/usr/bin/time` wrapper boundary as the earlier CLI benchmark. RSS is child peak resident memory. No command raises resource limits. Host contention makes these owner-authorised timings provisional.

### djpeg 3.2.1

| Case | Swift ms, rounds 1 / 2 | djpeg ms, rounds 1 / 2 | Swift latency reduction | Swift RSS MiB | djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| noise-2048 | 26.633 / 26.677 | 29.610 / 29.449 | 10.05% / 9.41% | 22.641 / 22.641 | 2.844 / 2.844 |
| noise-3072 | 49.377 / 50.065 | 58.735 / 59.324 | 15.93% / 15.61% | 42.672 / 42.672 | 2.844 / 2.844 |
| mixed-3072 | 39.335 / 41.216 | 51.758 / 54.410 | 24.00% / 24.25% | 34.641 / 34.641 | 2.844 / 2.844 |

[Complete raw samples and command receipt](new-cli/ca0-3.2.1/receipt.json).

### djpeg 3.2.0

| Case | Swift ms, rounds 1 / 2 | djpeg ms, rounds 1 / 2 | Swift latency reduction | Swift RSS MiB | djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| noise-2048 | 26.263 / 26.221 | 28.861 / 28.888 | 9.00% / 9.23% | 22.641 / 22.641 | 2.844 / 2.844 |
| noise-3072 | 49.207 / 49.696 | 58.401 / 58.401 | 15.74% / 14.91% | 42.672 / 42.672 | 2.844 / 2.844 |
| mixed-3072 | 39.291 / 39.553 | 51.727 / 52.198 | 24.04% / 24.22% | 34.641 / 34.641 | 2.844 / 2.844 |

[Complete raw samples and command receipt](new-cli/ca0-3.2.0/receipt.json).

All three newly admitted inputs beat both pinned djpeg versions in both rounds, with exact samples. All three peak process-memory comparisons still favour djpeg. These results are not pooled with the preceding five CLI wins at a different source pin; a complete current-source CLI matrix remains a later final gate. Native controls establish exact source-to-source output and retain every timing outlier, not a universal speed claim.

## Remaining work

Current parser source has not run remote CI, an ASan CLI suite, full-suite sanitiser tests or other-platform/device qualification. The preceding C source has its own platform snapshots; no historical pass is presented as this source. DCT workspace and single-worker decoding work continues separately. Small CLI latency and process memory remain competitive gaps. No stable release, completed goal or measured memory reduction is claimed.

[Manifest](manifest.json) preserves raw text hashes and original paths. Executables, object files, image payloads and large logs are omitted; the receipts retain their identities.
