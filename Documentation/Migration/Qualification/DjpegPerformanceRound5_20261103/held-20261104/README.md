# Held and rejected experiments, 4 November 2026

None of these experiments is selected production code. The qualified checkout remains `bbd6aede3ad2088caed4f6a06193a027b50d4857`, whose production code matches parser candidate `ca0c1e8`. Suite policy remains 0.10.0. All timings are provisional under owner-authorised shared-host contention.

| Experiment | Measured result | Decision |
|---|---|---|
| Exact block-local FMA, 256-block windows and tiny DC helper, `ba2771e` | 76 focused tests; 36 exact DCT pairs and 32 exact lossless pairs. Late-AC DCT improved about 19–22%, but ramp512/2048/3072 regressed about 16–24% in both rounds. | Held. No full safety, RSS or djpeg qualification of this composition. |
| C row-entry alignment, `5edcc5d` | All 96 targeted processes matched source samples. Aligned candidate ramp medians were about 16%, 19% and 19% slower than its original entries. | Rejected. The relinked original control did not reproduce the earlier regression; its different executable layout cannot overturn the earlier failed gate. |
| Standalone certified mirror IDCT | 21 datasets / 33,900 blocks / 2,169,600 integer samples matched the frozen FMA reference. The copied exact graph also matched its Float bits. Rounding-boundary and invalid-domain checks passed. Dense512 transform timings were about 2.8–2.9 times the reference cost. | This implementation is rejected on performance. No product source changed. |

The FMA composition's [decision](fma-composition/decision.json), [DCT results](fma-composition/dct.json), [lossless results](fma-composition/lossless.json) and source/build receipts retain the failed selection gate. Its 128 KiB pipeline payload is an allocation design, not measured RSS for this source. Earlier memory measurements belong to their own source revisions.

The alignment [decision](alignment/decision.json), [code-generation gate](alignment/build1/codegen-gate.json), [raw results](alignment/targeted-run1/results.json) and [independent review](alignment/targeted-run1/independent-review.json) preserve both the result and its executable-layout limitation. Original function instructions/calls/frames were unchanged; that fact did not establish a performance cause. The initial conservative padding-parser rejection and its correction are retained.

The mirror [results](mirror/RESULTS.md), [correctness receipt](mirror/runs/lane-check-fix/correctness.json), [root review](mirror/runs/lane-check-fix/root-correctness-review.json), [timing receipt](mirror/runs/lane-check-fix/timing.json) and [decision](mirror/decision.json) preserve the exact commands, inputs and binary identity. The initial probe-only compile failure is retained separately. The numerical reference is the held `ba2771e`, not a newly accepted decoder. Timings compare source-level transform twins with the same owning-buffer/output-allocation boundary and include certificate bookkeeping. They do not measure whole decoding, CLI launch, RSS or djpeg performance. No quality threshold was relaxed.

The manifest lists byte-identical original text evidence and a separate hash inventory for omitted binaries and verbose disassembly retained at their original local paths. The generated report is separately identified. Failed trials are not pooled with accepted benchmark wins.
