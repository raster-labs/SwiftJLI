# Planned C safety extension — not executed

This is a source/design receipt, not a test result. Both extensions are implemented in [v2-source](v2-source/README.md), but neither has been compiled or run. The original 3a5ef32 AC leaf's 42-test ASan / 1,145,828-case C sanitizer evidence does **not** automatically qualify these revisions.

## Source boundaries

- Current combined DC+AC target: `e0cfea0` (additional local inlining attributes), copied exactly in [v2-source](v2-source/README.md). Earlier1db53e8 and9f11312 source copies and the unexecuted version1 harness remain preserved. The emitted-code safety gate must use the current pin even though algorithm and ABI are unchanged.
- Lossless row: `06eff27`, independently pinned source/header copies in the same receipt.
- Build separately against each header and original implementation. Their status enums and exported entrypoints differ. Do not merge sources merely for this diagnostic. Any later integrated source gets a new pin, source hashes and commands.
- Retain the existing tested `ac_safety.c` unchanged. Reuse its independent canonical encoder/table generator, interval-expanded lookup construction, fixed buffers, poisoned logical tails, deterministic PRNG and result counters in new extension files.

## Shared cases and assertions

Use at least 1,048,576 fixed-seed bounded random cases **per new entrypoint**, plus explicit cases below. Exercise reader available counts 0–64, every physical offset through the declared input end, lengths 0–17 exhaustively and 0–512 randomly, eight byte alignments, short and 9–16-bit canonical codes, table capacities 255/256, FF-free bulk loads, stuffed FF00, FF at each word position, restart/EOI/other marker bytes, dangling FF, empty and truncated input. Keep metadata valid; arbitrary corrupted internal tables are outside the leaf contract.

Input, reader state, tables, output, previous predictor and result use distinct fixed storage unless the row alias case explicitly permits only input/output overlap. Check every result/status, offset monotonicity and range, available <=64, canaries and untouched bytes outside the permitted output prefix. Poison exact logical input tails and output guard ranges. Validate poison setup in the extension before invoking the leaf. Avoid signed overflow and shifts by the full width in the harness itself.

For independently encoded cases, an encoder-side bit ledger records symbol and magnitude lengths. A physical-byte-to-delivered-bit map counts ordinary bytes and complete stuffed FF00 pairs but not marker/dangling FF bytes. `initialAvailable + deliveredBitsAtPublishedOffset - finalAvailable` checks logical consumption at known stages. Compare valid buffered suffix bits without inspecting unused accumulator bits (special-case available=64). This ledger is not a second entropy decoder. Existing Swift differential tests remain responsible for exact physical-prefetch and next-read equivalence across arbitrary malformed streams.

Use raw input backed by UInt16/UInt32 objects as well as byte arrays, and pass it through the public `const void *` interface. Representation access belongs inside C. Do not introduce Swift typed binding assumptions or force a copy/rebind to make a case pass.

## Combined DC+AC

Generate DC symbols 0–16 and malformed symbols 17,31,32,63,64,127,255. Cover AC categories 0–15, EOB, ZRL, unusual zero-category runs, and final-coefficient/run overflow. DCT category 16 consumes **16 magnitude bits**; it is not the lossless -32768/no-extra-bits special case.

For precision 8 and 12, test reconstructed DC exactly at both inclusive limits +/-2^(precision+2), one beyond each limit, zero and signs near zero. Use prior predictors at those limits; also use Int32.min/max as defensive private-state probes to check the Int64 addition, recording them separately from reachable public decoder states. Construct category-16 cases that succeed at precision 12 by cancelling against a boundary predictor, and cases that fail its range check.

Assert stage-specific publication:

1. Invalid arguments: state, predictor and the entire sentinel output remain unchanged.
2. DC symbol/magnitude/invalid-width/range failure: output and previous predictor remain unchanged. Reader state reflects the completed/partial DC read. Invalid width reports the offending category after consuming its symbol and before magnitude consumption.
3. Valid DC followed by AC failure: previous predictor is updated, output has the exact completed AC prefix, output[0] remains zero. AC partial output/cursor can also be compared with the already-qualified AC entrypoint started from the encoder-ledger DC state; label this as shared-helper metamorphic coverage, not an independent oracle.
4. Full success: output[0] is the reconstructed DC and all 63 AC coefficients match the encoder model.

Place marker/truncation boundaries before/inside/after DC code, DC magnitude, first AC code, AC magnitude and EOB. Exercise invalid precision 0,7,9,13,16,UINT_MAX; wrong output/lookup counts; null required pointers; available 65; offset count+1/SIZE_MAX and table value_count257. Only pass valid accessible allocation extents; a huge claimed length over a small buffer would violate the contract rather than test checked state.

No combined-DCT alias test may overlap input/output/predictor/metadata/state: the entrypoint explicitly requires disjoint storage and uses restrict. Poison guards and sentinel checks must respect that precondition.

## Lossless left-predictor UInt16 row

Generate every category 0–16 and malformed values above16 with short and long codes. Category0 is zero difference; category16 is **-32768 with no magnitude bits**. Encode positive/negative magnitudes at each category boundary. Check seeds 0,1,2048,32767,32768,65534,65535, wraparound in both directions and accumulated modulo65536 values. Cover row lengths 1,2,3,7,8,9,63,64,65,255,256,257,65534,65535; bound random rows separately to keep the million-case corpus small and repeatable.

Validate returned first/last/written fields; exactly written*2 little-endian bytes may change, and the remaining output sentinel/padding must remain intact. On entropy failure, compare the complete sample prefix, result and logical consumed bits. Test invalid count0/65536/SIZE_MAX, seed65536/UINT_MAX, undersized output, null pointers and invalid reader/table extents. Invalid arguments must leave state, result and every output byte unchanged.

Use odd output bases and buffers whose declared C objects are UInt16/UInt32; writes occur through the `void *` interface and character access. The Swift test already covers an odd raw slice of UInt16-bound storage; standalone sanitizer coverage supplements it.

Input/output overlap is permitted **only for this row leaf**. Use exact overlap, +/-1 byte, partial overlap and output over already consumed input. State/table/result remain disjoint. For aliases:

- Poison outside the union of live input/output extents, avoiding false positives when valid writes land beyond the input extent or valid reads outside the output extent.
- Snapshot the shared buffer; verify every byte outside the declared written output prefix is unchanged, including bytes still inside the input range. This catches output overrun that union poisoning alone cannot detect.
- Compare one N-sample call against repeated count=1 calls with the previous returned sample as seed, on two identically aliased fixed buffers. The state/prefetch/partial writes must match. This is a documented metamorphic row-boundary/alias check, not an independent codec oracle.
- Do not compare overlap that overwrites future entropy against the pristine encoder output: those writes intentionally change future input. Check memory safety, result/state bounds and the one-row/one-sample equivalence instead.

## Execution and acceptance receipt

After a CPU grant, compile each extension with the flags in [planned-config.json](planned-config.json), retain Clang version, exact command, environment, source/header/harness and binary hashes, stdout counters, stderr, elapsed duration and exit code. Run ASan+UBSan with halt-on-error. Record random/boundary/encoded/alias/invalid case counts separately, status and category coverage, and the fixed seed.

A clean sanitizer result qualifies only that bounded safety slice. It is not performance acceptance, whole-suite/cross-platform qualification or a substitute for Swift differential/oracle tests. Retain any harness setup/expectation failures separately from production defects. No flags or test code enter shipping Package.swift.
