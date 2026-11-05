# Qualified block-local decoding checkpoint — 4 November 2026

**The competitive goal remains open.** Tested source `6e763ec2099e162bae52a40109ff74269ea9899f` combines exact ARM64 block-local DCT, smaller bounded windows, serial C entropy, four-symbol lossless rows, small left-predictor storage removal and compact DC zero-pair decoding. It repairs the real empty-array race found in parent `bbc9ebe`. The source baseline is `ca0c1e874177f429ed199f3ed8ef6ac1315ee66a`; suite policy is 0.10.0. Apple floor 26.0, Swift manifest minimum 6.2 and primary Swift 6.4 remain unchanged. The executed toolchain was Swift 6.4.2 / Xcode 27.2. A [host identity readback](qualification/host-identification.json) after qualification confirms macOS 27.0.1, M4 Max, 16 physical cores and 64 GiB RAM; benchmark-time load is recorded separately in each run.

## Behaviour and memory

Eligible ARM64 Accelerate greyscale DCT uses 256-block windows and consumes all coefficients before reusing their storage for Float reconstruction and final sample tiles. The established ascending fused multiply-add graph, separate centring, clipping, output precision and ownership remain unchanged. A pipeline owns two coefficient/output slots (128 KiB instead of 768 KiB); serial reconstruction owns at most 64 KiB. Scalar and other architectures retain the existing GEMM paths. Only the caller accesses provider output; workers join before internal borrows end. Actual RSS is measured separately below.

The small lossless left-predictor route keeps its one necessary history sample locally and retains cancellation/restart bounds. The original C zero-code row kernel groups four proven symbols without crossing a skipped refill. The compact DC shortcut skips only proven one-bit zero-category DC/EOB pairs within existing row, batch and restart bounds. Unsupported tables and modes retain their original paths. No external codec is a product dependency, and no quality or resource ceiling is relaxed.

Parent bbc passed its assertions but **failed ThreadSanitizer**, with three writes to global `_swiftEmptyArrayStorage` in zero-capacity uninitialised scratch constructors. The repair uses `[]` when scratch is absent, preserving positive-capacity construction. The same 133-test filter now passes without warnings or suppression. [Parent failure](parent-bbc/tsan-1/command.json), [trace](parent-bbc/tsan-1/tests.log), [repair review](qualification/source-audit.json).

## Executed qualification

| Check | Outcome |
|---|---|
| Full Release | 496 tests / 85 suites; exit 0 |
| Focused AddressSanitizer | 133 tests / 25 suites; exit 0 |
| Same focused ThreadSanitizer filter | 133 tests / 25 suites; exit 0, no warnings |
| CLI Release | 252 checks; exit 0 |
| Native lossless regression matrix | 16 cases × two rounds; every output exact |
| Native DCT regression matrix | 18 cases × two rounds; every output byte-exact |
| Independent large lossless oracle | Six profiles, 12 streams, 24 exact decoder outputs |
| Independent large DCT oracle | Eight profiles, 16 direction comparisons; maximum difference 1, limits 2/4 unchanged |
| Original C four-symbol standalone differential | 1,902,443 ASan/UBSan cases; target files byte-identical to qualified f104 |

[Source manifest](qualification/source.json), [Release](qualification/release-1/command.json), [ASan](qualification/asan-1/command.json), [TSan](qualification/tsan-1/command.json), [CLI](qualification/cli-checks-1/receipt.json), [oracles](qualification/oracles/summary.json), [C evidence attribution](qualification/c-standalone-attribution.json). Commands, compiler/source/fixture hashes, raw samples and exit statuses are preserved alongside these receipts. Fixture provenance remains the [round-two synthetic corpus](../../DjpegPerformanceRound2_20261102/README.md) and pinned supplemental generators in the receipts; no patient data is used.

Neither native matrix has a slowdown over 5% in both rounds. Individual outliers remain visible, including flat512 lossless +22.52% then −22.92%; this is not a controlled no-regression guarantee. Ramp19 improves in both current rounds; the parent bbc's earlier failed ramp19 screen and its bounded fixed-binary diagnostic remain separate. Parent failures have not been deleted or relabelled.

## Allocated-output comparison with libjpeg-turbo 3.2.1

Both decoders use the same executable, retain compressed input and one complete output, and include output allocation in decoding time. Five warm-ups, 20 samples and two balanced rounds are unchanged. RSS uses three fresh processes per engine/case. Fixed full-sample quality checks precede timing. Four RGB/progressive cases still exceed the 8-bit threshold (difference 3 > 2), and are excluded before timing. The diagnostic's explicit large resource budgets do not establish default admission.

SwiftJLI has lower medians in both rounds for **11 of 12 admitted cases**; noisy 8-bit DCT is near parity. Single-worker DCT2048 remains about 13.3% slower. All five lossless cases use less RSS than libjpeg-turbo; all seven DCT cases use more, by 0.219–0.609 MiB. Fresh ca0/candidate comparisons show dense/noisy DCT RSS reductions of 0.531–0.766 MiB. Flat8 rises by 0.047 MiB; flat12 and mixed2048 tie. These are whole-process observations, not isolated attribution to one instruction or allocation.

Values below are the mean of two round medians for time and median of three fresh measurements for RSS. Raw per-round values remain in the [complete comparison report](qualification/owned-output/RESULTS.md) and [independent review](qualification/owned-output/independent-review.json).

| Case | Workers | Swift ms | Turbo ms | Swift RSS MiB | Turbo RSS MiB |
|---|---:|---:|---:|---:|---:|
| flat-19.jpg | 8 | 0.0071 | 0.0107 | 8.891 | 9.453 |
| ramp-19.jpg | 8 | 0.0076 | 0.0115 | 8.891 | 9.406 |
| noise-19.jpg | 8 | 0.0077 | 0.0116 | 8.891 | 9.406 |
| mixed-19.jpg | 8 | 0.0072 | 0.0109 | 8.922 | 9.406 |
| mixed-2048.jpg | 8 | 12.6959 | 19.0305 | 21.484 | 21.953 |
| dct12-512.jpg | 8 | 1.1399 | 1.3122 | 10.062 | 9.531 |
| dct12-2048.jpg | 8 | 15.7694 | 19.3026 | 20.469 | 19.953 |
| dct12-2048.jpg | 1 | 22.3668 | 19.7353 | 20.312 | 19.953 |
| flat-8-512.jpg | 8 | 0.0531 | 0.0772 | 9.297 | 8.984 |
| flat-12-512.jpg | 8 | 0.0599 | 0.1660 | 9.547 | 9.328 |
| noise-8-512.jpg | 8 | 1.0886 | 1.1121 | 9.797 | 9.188 |
| noise-12-512.jpg | 8 | 1.2983 | 1.3994 | 10.203 | 9.609 |

## Whole-process CLI comparison

The unchanged CLI method includes process launch, input reads, decoding and PNM output to `/dev/null`. It uses five warm-ups, 20 samples and two balanced rounds against each pinned djpeg version (3.2.0 and 3.2.1), with no resource overrides. Both Swift outputs must match exactly; lossless samples match djpeg exactly, and DCT12 differs by at most 1 within its limit 4. RGB/progressive exclusions remain 3 > 2.

For **each djpeg version**, all eight 2048²/3072² lossless pattern cases beat djpeg in both rounds. Every 19²/512² case remains slower. The original lossless2048 case is the same input as mixed2048 and is not a ninth unique win. All admitted CLI RSS results still favour djpeg. There is no individual or repeated elapsed slowdown over 5% against ca0 in these four matrices. See [all case/round results](qualification/cli-benchmark-1/summary.json), [commands and hashes](qualification/cli-benchmark-1/receipt.json) and [independent review](qualification/cli-benchmark-1/independent-review.json).

CLI values are means of two round medians. Repeated wins are determined per round, not from this display average.

### djpeg 3.2.1

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|
| lossless16 512² | 9.110 | 9.108 | 7.486 | 7.367 | 2.812 |
| lossless16 2048² | 23.171 | 22.819 | 27.932 | 19.094 | 2.844 |
| dct12 512² | 9.709 | 9.494 | 7.578 | 7.641 | 2.203 |
| flat 19² | 8.239 | 8.155 | 6.321 | 6.453 | 2.750 |
| flat 512² | 8.743 | 8.633 | 7.496 | 7.062 | 2.812 |
| flat 2048² | 11.262 | 11.351 | 21.200 | 15.016 | 2.844 |
| flat 3072² | 14.353 | 14.120 | 38.234 | 25.641 | 2.844 |
| ramp 19² | 8.795 | 8.942 | 6.928 | 6.453 | 2.750 |
| ramp 512² | 9.652 | 9.535 | 8.260 | 7.297 | 2.812 |
| ramp 2048² | 18.002 | 14.612 | 27.332 | 17.609 | 2.844 |
| ramp 3072² | 28.015 | 21.428 | 50.583 | 30.234 | 2.844 |
| noise 19² | 9.130 | 9.056 | 7.105 | 6.453 | 2.750 |
| noise 512² | 10.436 | 10.423 | 8.742 | 7.547 | 2.812 |
| noise 2048² | 28.790 | 29.467 | 32.242 | 22.641 | 2.844 |
| noise 3072² | 53.173 | 53.576 | 62.634 | 42.680 | 2.844 |
| mixed 19² | 9.204 | 9.213 | 7.181 | 6.453 | 2.750 |
| mixed 512² | 10.322 | 10.251 | 8.542 | 7.359 | 2.812 |
| mixed 2048² | 24.072 | 24.137 | 28.820 | 19.094 | 2.844 |
| mixed 3072² | 42.089 | 42.114 | 55.675 | 34.641 | 2.844 |

### djpeg 3.2.0

| Case | Prior Swift ms | Updated Swift ms | djpeg ms | Updated RSS MiB | djpeg RSS MiB |
|---|---:|---:|---:|---:|---:|
| lossless16 512² | 8.976 | 8.874 | 7.188 | 7.359 | 2.812 |
| lossless16 2048² | 23.360 | 23.138 | 27.602 | 19.094 | 2.844 |
| dct12 512² | 9.718 | 9.646 | 7.469 | 7.645 | 2.203 |
| flat 19² | 8.270 | 8.335 | 6.161 | 6.453 | 2.734 |
| flat 512² | 8.599 | 8.455 | 6.950 | 7.062 | 2.812 |
| flat 2048² | 10.642 | 10.815 | 18.356 | 15.020 | 2.844 |
| flat 3072² | 14.416 | 14.539 | 32.962 | 25.641 | 2.844 |
| ramp 19² | 8.761 | 8.765 | 6.866 | 6.453 | 2.742 |
| ramp 512² | 9.504 | 9.488 | 8.153 | 7.297 | 2.812 |
| ramp 2048² | 17.530 | 14.645 | 27.458 | 17.609 | 2.844 |
| ramp 3072² | 28.019 | 21.448 | 51.003 | 30.234 | 2.844 |
| noise 19² | 8.840 | 9.138 | 6.952 | 6.453 | 2.734 |
| noise 512² | 10.319 | 10.288 | 8.467 | 7.547 | 2.812 |
| noise 2048² | 28.555 | 28.772 | 31.757 | 22.641 | 2.844 |
| noise 3072² | 51.256 | 51.525 | 61.058 | 42.676 | 2.844 |
| mixed 19² | 8.416 | 8.427 | 6.497 | 6.453 | 2.734 |
| mixed 512² | 9.661 | 9.734 | 8.044 | 7.359 | 2.812 |
| mixed 2048² | 24.090 | 23.903 | 28.212 | 19.094 | 2.844 |
| mixed 3072² | 42.660 | 42.558 | 55.139 | 34.645 | 2.844 |

## Limits and continued work

All timings are **provisional**, as authorised by the owner: unrelated VM activity persisted (about 95–194% CPU in owned-output snapshots). Only one agent build/test/benchmark workload ran at a time. No global winner, controlled final result or completed performance goal is claimed. Small CLI startup, single-worker DCT and DCT/process memory remain open. The separate selected-Huffman and bounded-C-run trials are not part of this qualified source. No new Intel/Linux/simulator/physical-device run or stable release is claimed for this checkpoint; prior-source CI remains historical.

The archive manifest identifies byte-exact original text, generated report text and omitted local binary identities. Additional exploratory evidence remains at its original source-pinned location. Public ABI JSON matches the baseline; no API or fidelity/copy policy changed. Source integration is recorded in [integration.json](qualification/integration.json); original user edits are preserved separately.
