# Decoder allocation experiment

This independent public-API consumer runs only on Linux with glibc. Its C allocator interposer is linked into the experiment executable, never the shipping SwiftJLI library. Run from the repository root:

```sh
python3 Scripts/run-allocation-probe.py --output-dir /tmp/swiftjli-allocation-probe
```

The runner builds release without sanitizers, records source/binary hashes and the immutable container identity, and retains raw allocation-size histograms. C calibration checks malloc, calloc, realloc, aligned allocation and frees; Swift calibration proves that an owned pixel allocation crosses the interposer. Three warmed repetitions cover allocating and padded caller-destination decode for five profiles at two sizes. Sample bytes, interpretation, allocation identity and zero-filled padding are checked outside the measured scope. Sources, compressed input, reference images and caller destinations predate that scope.

A second run deliberately copies every decoded frame inside the measured scope while preserving the decoder's output identity. The verifier must observe the extra frame-size allocation in all 60 positive controls. Thus it can catch this particular hidden-copy defect even when a pointer-identity assertion passes. It also requires one final-frame-size allocation for allocating decode and none for caller-destination decode in the baseline.

The measurement is process-wide **requested heap bytes allocated during each scope**, sampled at allocator return/free boundaries. It includes Swift runtime and compressed/parser/algorithm allocations. It excludes pre-existing allocations, allocator rounding/metadata, the interposer's static tables, direct mmap allocations and any transient internal realloc copy. It does not instrument memcpy, inline copies, stack storage or every possible allocator. Full-frame-size bins can coincide with unrelated allocations on different toolchains; verification then fails rather than reclassifying them automatically. Results are not total RSS, pure codec workspace, performance timings or a universal proof that copies never occur. Encode, cancellation/failure, other platforms and cross-codec paths need separate evidence. No sanitizer accounting is used.


## Concurrent work, failures and cancellation

`python3 Scripts/run-allocation-probe.py --operation stress --output-dir <new-dir>`
runs 28 scoped measurements and 28 retained-copy controls. Two input sizes,
five warm-ups and 2/32 joined operations cover concurrent encode/decode, invalid
final UInt12 samples, admission denial and processing-callback cancellation.
At most two operations run together, each with at most two workers. A baseline
must retain less than one full source frame after a joined batch. Each control
retains one copy per operation and must observe those bytes. Tiny residual
runtime allocations are reported, not labelled as codec leaks or hidden.
This extends the earlier single-operation evidence; it is not exhaustive allocator
fault injection or proof against smaller leaks. NativeExecutionTests separately
exercises cancellation after worker entry. The explicit test admission limits are
1 GiB workspace and 2 GiB total memory per operation.
