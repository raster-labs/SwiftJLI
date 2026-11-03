# Certified mirror prototype: executed result

**Do not integrate this implementation.** Numerical checks passed on this host, but the certificate prototype was2.72–2.97times slower than its source-level exact reference. No production code changed.

The source-only README and source receipts are intentionally frozen preparation records. This file records the later authorised execution; it does not rewrite those inputs.

## Executed gates

- Initial build exited1 because the probe called `contains` on SIMD8. Exact sources and logs remain under `runs/initial`. No codec/test execution occurred in that attempt.
- Authorised repair changed only that harness expression to an indexed0..<8 lane check; kernel/reference arithmetic remained unchanged.
- `run.py build --run-name lane-check-fix --cpu-grant`: exit0.
- `run.py correctness --run-name lane-check-fix --cpu-grant`: exit0.
- After independent receipt review, `run.py timing --run-name lane-check-fix --cpu-grant`: exit0.
- All pinned sources, objects, modules, modulemap/header, compiler, fixtures and binary remained unchanged during the successful gates.

## Numerical evidence

21datasets,33900coefficient blocks and2169600integer samples matched the frozen ba277 reference. The copied exact transform graph also matched all2169600reference Float bit patterns. Of those integer samples2166276were certified,2268used ambiguous-pixel exact fallback, and1056used explicit domain fallback in internal extreme tests. No fixture row required domain fallback.

The actual maximum stored-Float mirror residual was3.2782554626464844e-7. Both actual basis/mirror bit arrays and upward weights are in correctness.json. Dense512fixture ambiguous-pixel rates were0.2258% for DCT12,0.0347% for noise8 and0.4871% for noise12. Counts include all64block samples, including padding for tiny/odd fixtures.

The boundary corpus covered4350half thresholds with5neighbours each plus8interior/clipped rows:21758rows. It exercised162888ambiguous pixels and11176certified pixels.12invalid-certificate cases and12invalid-domain rows also passed. Row-level boundary inputs are separate from encoded-JPEG coefficient cases.

## Standalone transform medians

| Dataset | Blocks | Exact ms | Certified ms | Ratio |
|---|---:|---:|---:|---:|
| synthetic-dense-8 | 512 | 0.084104 | 0.249646 | 2.968x |
| synthetic-dense-12 | 512 | 0.089208 | 0.251688 | 2.821x |
| fixture-dct12-512.jpg | 4096 | 0.769500 | 2.213145 | 2.876x |
| fixture-flat-8-512.jpg | 4096 | 0.781875 | 2.236646 | 2.861x |
| fixture-flat-12-512.jpg | 4096 | 0.761334 | 2.240937 | 2.943x |
| fixture-noise-8-512.jpg | 4096 | 0.776375 | 2.227958 | 2.870x |
| fixture-noise-12-512.jpg | 4096 | 0.780771 | 2.273354 | 2.912x |
| fixture-flat-8-19.jpg | 9 | 0.001875 | 0.005104 | 2.722x |
| fixture-flat-12-19.jpg | 9 | 0.001625 | 0.004521 | 2.782x |
| fixture-noise-8-19.jpg | 9 | 0.001625 | 0.004500 | 2.769x |
| fixture-noise-12-19.jpg | 9 | 0.001625 | 0.004459 | 2.744x |
| fixture-late-ac-8-512.jpg | 4096 | 0.782125 | 2.210521 | 2.826x |
| fixture-late-ac-12-512.jpg | 4096 | 0.778875 | 2.198230 | 2.822x |

The same binary ran both source-level arms with a common exact first pass and owning-buffer/output-allocation boundary. Order alternated, with5warmups and20measured samples per arm. All timed outputs were compared outside the timer. Domain checks, certificate evaluation and bookkeeping are included. These are provisional shared-host transform timings, not full decoder/djpeg/RSS results or timings of the frozen in-place API. Flat blocks were transformed here to exercise the prototype; this does not model the earlier DC-only shortcut in the production dispatcher.

## Scope and remaining gates

The proof/correctness experiment shows that actual-Float-basis certification can preserve the tested integer samples with low pixel fallback on the inspected dense fixtures. Its current overhead outweighs the arithmetic saving. This does not prove that every possible cheaper certificate implementation must be slow. No further optimisation or timing is implied by this result.

The FMA256 composition used as a numerical reference remains unaccepted for production. The candidate does not implement or alter Float32 output, product lifecycle/executor behaviour, cancellation/provider borrows or resource limits. No new ASan/TSan, architecture/platform qualification, public-codec integration or external oracle gate was run. CPU was released after the timing receipt completed.
