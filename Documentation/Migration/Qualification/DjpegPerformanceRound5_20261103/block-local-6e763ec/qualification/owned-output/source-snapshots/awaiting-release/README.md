# Prepared owned-output comparison — 6e763ec

Source-only preparation for `6e763ec2099e162bae52a40109ff74269ea9899f`, contract 0.10.0. No comparator build, latency run or RSS run has executed at preparation. This preparation is blocked by an explicit `artifactsReady: false` gate until the corrected Release objects/modules and their build attribution are available. The preceding bbc preparation remains preserved in its separate directory. The four comparator implementation files (`Compare.swift`, `jpeg_bench.c`, its header and module map) are byte-identical to the qualified `c-final-5f9e1cf/owned-output` harness. Production objects are imported from the existing Release build, not rebuilt by these scripts.

## Unchanged measurement

The single fresh executable contains SwiftJLI and the exact pinned static libjpeg-turbo 3.2.1 archive. The C helper remains development-only; the product does not depend on it. Decode timing includes decoder setup/workspace and allocated complete output through finish/return. The compressed Data remains retained; output checks and owner destruction occur after the timer. No decoded output copy, file writing or smaller bit depth is introduced.

The case list and order, worker ceilings, libjpeg settings and quality limits remain unchanged: five lossless cases at tolerance 0, seven admitted greyscale DCT cases at tolerance 2 for eight-bit or 4 for twelve-bit, and four RGB/progressive cases that previously exceeded tolerance 2. Each process first compares every output sample and verifies descriptor/layout equality. A quality failure excludes that case before latency measurement; it is never reported as a speed win.

The preflight compares every sample once per timing process. Measured decode iterations check only the first and last output values after the timer, exactly as in the qualified harness; this is not a full-output comparison on every measured iteration.

Each admitted case uses five warm-ups and twenty measured iterations per decoder, interleaving decoder order, in each of two outer rounds. Fresh-process RSS uses the unchanged `memory-swift` and `memory-turbo` modes, retaining compressed input and one complete owning output, with three alternating-order pairs per admitted case. Full-output byte count and FNV identity must match the pre-timing quality gate. FNV is an identity aid, not a replacement for that full per-sample comparison.

The diagnostic overrides remain Swift workspace 8 GiB / total memory 10 GiB and libjpeg fixture output 512 MiB / dimensions 8192. These runs do not establish default resource admission or replace CLI measurements. Same-process timing uses the same executable/runtime images; RSS compares fresh processes of that executable, one selected decoder per process.

## Fresh baseline RSS companion

A second executable links the frozen parser-baseline `ca0c1e874177f429ed199f3ed8ef6ac1315ee66a` objects/modules, the identical comparator Swift source and the **same compiled comparator C object**. It runs only `memory-swift`; there is no expanded baseline timing matrix.

After the current fixed-quality comparison succeeds, three fresh baseline/candidate RSS pairs run for each of the same twelve admitted cases, alternating order. Both retained outputs must have the same byte count and complete-output FNV as the current Swift quality result. Existing native full-output hashes separately cover baseline/candidate decoder equivalence; this companion adds no decoded output copy or full sample comparison to the RSS process.

The companion measures the complete current-candidate versus parser-baseline process memory delta. It is not an isolated causal estimate for one FMA instruction change: the source revisions contain several qualified changes. Historical `5f9` numbers remain context only; fresh ca0 pairs avoid relying on the earlier host state for the current memory comparison.

## Identities and failure retention

`prepared.json` pins both complete production source inventories, both Swift/C objects, imported modules and module-map umbrella headers, compiler binaries, SDK settings, the static library and public libjpeg headers, the eleven-plus-four unique fixture files, original harness/qualification receipts and the current Release source/build attribution. There are sixteen cases because the same 2048 DCT input appears with worker ceilings eight and one.

The outer scripts add identity and failure controls only. They refuse existing action receipts, snapshot source/plan at the initial build, retain command stdout/stderr and timed-process `/usr/bin/time -l` output, finalise failure receipts, and require unchanged source/artifact/fixture/compiler/binary identities. Each action uses separate logs. New source or a failed attempt requires a new run name; prior attempts are retained. `prepared.json` is a source-preparation record, not a result.

After a parent-granted exclusive CPU slot, the prepared sequence is:

```sh
python3 /private/tmp/swiftjli-round5-evidence/empty-scratch-fix/owned-output/build.py --run-name initial --cpu-grant
python3 /private/tmp/swiftjli-round5-evidence/empty-scratch-fix/owned-output/run.py --run-name initial --cpu-grant
python3 /private/tmp/swiftjli-round5-evidence/empty-scratch-fix/owned-output/build-baseline.py --run-name initial --cpu-grant
python3 /private/tmp/swiftjli-round5-evidence/empty-scratch-fix/owned-output/run-rss-baseline.py --run-name initial --cpu-grant
```

Run only the actions covered by the current CPU grant. Stop and retain the attempt on failed compilation, quality, identity or process checks. The baseline companion requires successful current results. All timing remains provisional on this shared host; input/output quality evidence is reported separately. No result or acceptance claim exists yet.
