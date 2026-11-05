# Bounded grouped greyscale trial: local performance gate passed

Base: `425bfa4b996c39b6fde727af4bdd795b62cc4652`. Candidate worktree: `/private/tmp/swiftjli-round5-parallel-stream`. Frozen baseline products: `/private/tmp/swiftjli-round5-425bfa4-products`. The rejected entropy Bool flag and optional DC-helper changes are absent.

Large qualifying sequential 1×1 greyscale frames use at most eight logical lanes. A serial entropy window contains lanes×1024 canonical blocks; each joined worker packs and transforms its own disjoint coefficient/output and Float scratch regions. The original 1024-block GEMM dimensions and tail sizes are retained. Pixels compact in place to raw bytes. No provider pointer enters the worker carrier. After every worker joins, the caller copies only active tile rows. Entropy, worker compaction and scatter retain bounded cancellation points.

Binding proof: all Int32 coefficient reads end before Float rebinding. UInt8 subscripting of UnsafeMutableRawBufferPointer is explicitly an untyped byte view that does not change the memory binding. Float is trivial. For integer output, sample i is loaded before its one/two output bytes are written at an earlier or equal offset; the write cannot reach any later four-byte Float. No consumed Float value is read again. Float output preserves its existing representation on supported little-endian hosts. Binding restores before worker return or throw. The caller subsequently reads raw bytes only; the next entropy block resets all 64 Int32 slots. All owners remain retained through NativeOperation.perform's join on both success and error.

Primary API authority: [Swift raw-buffer implementation and documentation](https://github.com/swiftlang/swift/blob/main/stdlib/public/core/UnsafeRawBufferPointer.swift.gyb) and [Apple raw-pointer documentation](https://developer.apple.com/documentation/swift/unsafemutablerawpointer). The implementation uses raw-buffer byte subscripting; it does not reinterpret the storage through a typed UInt16 pointer while Float remains bound.

Resource proof: each logical lane reserves 1024×64×(4-byte Int32+4-byte Float)=524,288 bytes. Two lanes reserve 1 MiB; eight lanes reserve 4 MiB. Compaction adds no array or final-image copy. The unchanged compressed×64 and fixed 1 MiB allowances, and every decoded/compressed/total ceiling, still apply. Reservation is distinct from measured peak workspace. Large default memory could improve substantially without yet beating C's owned-output RSS; acceptance requires paired measurement and at most 5% latency regression.

The public provider contract remains unchanged: concurrent work never receives its borrowed mutable pointer. The separate root RGB contract repair belongs to the pinned baseline. SIMD/scalar output, cancellation, lifetime and sanitizer qualification remain pending.

## Executed evidence

Candidate `b0266d8a68adae6a0e570c72a5fbcfe588821f04` passed 35 focused Release tests in 8 suites (exact command and exit 0 in release-command.json). Independent source review found no actionable binding, race or bounds issue. Accelerated 12-fixture and scalar 6-fixture matrices each ran two alternating-order paired rounds, with every output SHA256 and byte count exact. Accelerated DCT12-2048 improved 9.85% and 10.18%; scalar DCT12-2048 improved 7.73% and 4.76%. No accelerated fixture regressed more than 5% in both rounds; all scalar fixtures improved. These are paired comparisons with Swift baseline 425, not claims against djpeg.

Fresh-process DCT12-2048/worker8 median RSS was 56,934,400→23,412,736 bytes (58.88% lower). The three candidate readings were 23,412,736; 23,412,736; 23,429,120. Worker 1 remained within 16KiB, and 512 controls within 16–49KiB. The 32MiB reduction matches the replaced whole-frame coefficient/Float planes and worker outputs: project workspace 36MiB→4MiB. Full raw timing samples, object/source hashes, commands and RSS triples are retained. Host process snapshots accompany the timings.

Integrated ASan/TSan and remote platform CI remain required before final acceptance. No such results are claimed here.
