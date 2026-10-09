# JPEG 2000 ↔ predictive JPEG integration

This development-only package tests SwiftJLI against SwiftJ2K pinned at
`be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`. Neither shipping library acquires a
dependency on the other. Only unsigned greyscale lossless Part 1 JPEG 2000 and
SOF3 JPEG are exercised; this is not HTJ2K, JPEG-LS or JPEG XL qualification.

Run from the SwiftJLI repository with a new output directory:

```sh
swift run --package-path Examples/CrossCodecIntegration CrossCodecIntegration /new/evidence
python3 Scripts/verify-cross-codec-outputs.py --input /new/evidence --output /new/oracle-evidence
```

The oracle check needs lossless-capable libjpeg-turbo `djpeg` and OpenJPEG
`opj_decompress`, strictly as development tools. It verifies every sample in all
12 compressed outputs against the independently specified integer pattern.

Six cases cover odd widths, non-square dimensions, 12/16 meaningful bits,
extrema, different source/destination strides, sentinel padding, both directions,
two concurrent reader encodes, exact byte/sample comparisons, and mutation
rejection after sealing. SwiftJLI processing-callback cancellation is checked for
encode and decode; a destination cancelled before writing must remain reusable.
Unsupported big-endian input must reject under both copy policies. No supported
layout conversion or in-kernel cancellation is inferred from those last checks.

Each adapter retains a sealed owner and forwards scoped reads. It creates no
pixel array and preserves the allocation identity. Completed compressed files
are written only after the hand-off for independent verification.

On Linux/glibc, the test-only `HeapProbe` interposer measures destination
allocation, decode and the two simultaneous reader encodes together. Calibration
must detect C and Swift allocations. A second process with
`SWIFTJLI_COPY_CONTROL=1` deliberately copies the entire final destination while
measurement is active. Retain stdout from each execution, then run:

```sh
python3 Scripts/verify-cross-codec-heap.py --baseline normal.log --control copied.log
```

The check requires one destination-sized allocation normally and exactly two
with the control, using the calibrated Swift array overhead. It detects these
tested full-frame allocations; it is not exhaustive copy instrumentation, pure
workspace accounting, Apple allocator evidence or a leak test. No interposer is
linked on Apple, where ASan and TSan are run separately. The allocator product
and unsafe linker settings exist only in these development packages.

The retained integration evidence also includes Linux `strace` of file opens and
process execution: the only write opens are the 12 final compressed outputs and
the only executed program is the harness. No intermediate decoded image or
external codec process occurs during the traced integration run.
