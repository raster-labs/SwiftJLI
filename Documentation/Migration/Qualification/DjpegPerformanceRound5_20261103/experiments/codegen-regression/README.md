# Large lossless kernel code-generation regression audit

Read-only investigation of the repeated large-ramp regression in round five. No production code was edited by this audit and no build/profile/benchmark was run. Disassembly and hashes use retained binaries/objects.

## Identities

- Baseline production: `0a8acd7`, unchanged at `bbb0b1a`; object `c98eeb52d679a6879d84dc91ce1ca313e89d2dc003e70e5f666f2c16f436e9cf`.
- Initial shared-kernel polling candidate `684065c9349fd6ccd7713b4992a1ec20ea0f9e02`: object `d3ed95dc82fe9cfbed90114f3055ba905512425a5d6202055239b081f924c2a6`; retained native binary `c22bd6fe6c1bc9d4f575af8934404283de4322ee0b8e0f6b1c80cb5ad5897ceb`.
- Separate small-kernel candidate `bcd0903a148aef79f8940ad18e1eea442e288033`: object `4b9ac659d9e9b91ad93be66a0c9111be11e33c9001f4d29d78e35b4f50d57904`.
- Explicit `@inline(__always)` trial `9346db0`: retained object was byte-identical to the preceding candidate. The rebuilt per-file object timestamp was newer than source. An initial stale-cache suspicion was therefore withdrawn; the verified conclusion is that this hint did not change emitted machine code.
- Explicit local width/height/Pt-bound trial `3c69e70e0b28f5bb21c688df4659faa54e24c2ed`: object `98541d243c8d3e07966a49fec7cae823ef4ac54f84dc6698aada78853b596e84`. A stable read was copied to `guard-object.o` solely for disassembly; do not publish the generated object in a text-only evidence archive.

`identity.json` pins initial objects and linked native executables. `*-linked.txt` files come from the retained isolated-small-kernel benchmark executables, so call addresses are resolved. Other disassembly files use relocatable objects and contain unresolved relocation addresses.

## Finding

Round-four code has no standalone `losslessGrayInto`: the compiler inlined it into the validated caller. The first attempt added bounded row polling to the shared scalar kernel (`rowsPerCheck = max(1, 1024 / width)`) so narrow images could avoid a check per row. Its `684065c` binary instead has a 468-line outlined kernel and no halfword stores. Although wide rows retained their old check frequency, their generated inner loop changed.

`bcd0903` then moved the polling state to a separate `@inline(never)` small kernel, selected only below 16,384 samples, and restored the large source loop verbatim. The optimiser still emitted the large kernel separately (456 disassembly lines), so source restoration alone did not restore the original specialisation.

The caller establishes dimensions in `1...65535` and point transform `0 <= Pt < precision <=16`. In the outlined candidate those facts are lost. Each UInt16 sample now incurs general signed-shift range handling, negative/at-least-64 shift cases, index/clamp work and two separate byte stores. The baseline uses one bounded shift, clamp and halfword store. This gives a concrete hot-loop mechanism consistent with the cheap ramp workload regressing; constructor allocations alone do not explain per-sample work.

Examples in linked executables:

- Baseline predictor-1 loop around `0x10003fa7c` performs `lsl`, clamp and one `sturh` at `0x10003fa40`.
- Candidate loop around `0x10003a9fc...0x10003aa40` repeatedly checks shift range and writes `sturb`/`strb` separately.
- Both revisions already call `losslessDifference` per sample; that call is not new.
- Both `fastDecodeLosslessDifference` overloads have the same normalised instruction shape in the old/new objects. HuffmanTable retains the same eight-array field layout; an empty encoder-only map is not a direct hot-reader layout change.

The initial matrix records ramp2048 regressions of 19.45% and 21.38%. After small-kernel separation the same case regresses 23.46% and 27.12%. These repeated regressions must not be dismissed as host noise. Other cases did contain severe host outliers: the isolated matrix's maximum raw noise3072 observation reached 208.161 ms, and its second-round baseline medians were inflated. Those measurements remain in the raw evidence; aggregate apparent wins caused by an inflated baseline are not accepted.

## Intervention review

An explicit pre-loop guard on dimensions `1...65535` and Pt `0...15` repeats existing caller facts and does not reject any previously admitted input. The rebuilt guard kernel shrank from 456 to 365 disassembly lines. General signed-shift branches disappeared, restoring direct `lsl`. **Halfword-store fusion was not restored**: the UInt16 branch still has two byte stores and separate high-byte clamp work.

The parent then ran the same 16-case public allocating-API matrix, with five warmups, twenty individually measured decodes, and two reversed-order rounds. Every baseline/candidate output matched the complete synthetic source bytes. The parent also recorded 408 release tests in 64 suites passing. The repeated 20–27% ramp2048 regression is absent in the local-bounds matrix. The timing results below are independently recalculated from the stored samples; negative time changes mean faster, positive changes mean slower.

| Case | Mean round-median baseline → guard ms | Time change | Round 1 / round 2 time changes |
|---|---:|---:|---:|
| flat-512 | 0.095740 → 0.093677 | −2.15% | −4.54% / +0.19% |
| flat-2048 | 0.826396 → 0.802084 | −2.94% | −3.53% / −2.35% |
| flat-3072 | 2.025313 → 1.784875 | −11.87% | −12.17% / −11.58% |
| ramp-512 | 0.709583 → 0.675792 | −4.76% | −1.20% / −8.10% |
| ramp-2048 | 11.237885 → 10.561302 | −6.02% | +0.03% / −11.33% |
| ramp-3072 | 23.600282 → 23.897021 | +1.26% | +7.05% / −4.10% |
| noise-512 | 2.246344 → 2.317417 | +3.16% | +5.89% / +0.54% |
| noise-2048 | 36.985261 → 36.056094 | −2.51% | +1.82% / −6.37% |
| noise-3072 | 81.079302 → 82.820010 | +2.15% | +2.97% / +1.37% |
| mixed-512 | 0.818906 → 0.816927 | −0.24% | +0.45% / −0.93% |
| mixed-2048 | 13.074719 → 12.812917 | −2.00% | −0.19% / −3.62% |
| mixed-3072 | 28.394385 → 29.839979 | +5.09% | +1.09% / +8.90% |

This does not establish broad regression-free performance. Ramp3072 round one, noise512 round one and mixed3072 round two each exceed a 5% regression threshold. Mixed3072's aggregate is 5.09% slower and requires follow-up. Raw maxima and p95 are retained, including a 136.306 ms noise3072 observation in the guard matrix. All timings remain provisional under unrelated host workloads; no outlier was dropped and no result is recast as clean-host acceptance.

The separate tiny matrix groups 500 public allocating decodes per timed sample and **includes output release**, whereas the individually timed native matrix excludes output destruction. These methods must not be pooled. Against the round-four baseline, the guard candidate's batched tiny measurements were:

| 19² case | Baseline → guard µs/decode | Time change | Round 1 / round 2 changes |
|---|---:|---:|---:|
| flat | 7.995188 → 6.279146 | −21.46% | −19.46% / −23.46% |
| ramp | 9.114563 → 6.702980 | −26.46% | −31.26% / −20.84% |
| noise | 8.771313 → 6.895229 | −21.39% | −22.28% / −20.47% |
| mixed | 8.139125 → 6.515896 | −19.94% | −19.12% / −20.77% |

All tiny full-output verification gates passed. These improvements belong to the integrated candidate (setup, polling and other source-pinned changes), not solely to the local guard. They are public-library observations, not whole-process CLI wins.

The parent is preparing a subsequent bounded trial using the existing zero-run decoder's raw `storeBytes(of: shifted.littleEndian, toByteOffset:x*2, as:UInt16.self)` idiom in the shared store helper, retaining the same clamping and checked destination ranges. The supported raw store does not require natural alignment. That trial is not part of the results above. It must recheck misaligned/padded output, point transforms, tiny and wide-lookup paths, and performance; this audit did not implement it.

## Raw evidence locations

- Initial shared polling: `/private/tmp/swiftjli-round5-evidence/parser-polling-native.json` and retained `parser-polling-native-{baseline,candidate}` executables.
- Separated kernel: `/private/tmp/swiftjli-round5-evidence/isolated-small-kernel/native.json` and corresponding JSONL, compile logs and executables.
- Ineffective inline hint: `/private/tmp/swiftjli-round5-evidence/inlined-large-release-tests.log`; frozen unchanged object under `/private/tmp/swiftjli-round5-pre-scratch-products/`.
- Local bounds: `/private/tmp/swiftjli-round5-evidence/local-bounds/native.json`, `tiny-comparison.json`, their raw JSONL/commands/hashes, and `/private/tmp/swiftjli-round5-evidence/local-bounds-release-tests.log`.

The raw JSON files pin the exact compiler, object, harness and fixture hashes. No source/runtime fallback to an external codec was introduced by these interventions; fidelity, precision, resource limits and suite policy remain unchanged.
