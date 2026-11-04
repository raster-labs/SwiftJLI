# Qualified JPEG allocation probe

This development-only macOS executable imports the public SwiftJLI product and measures one **first** inspect/decode call per fresh process. Inputs, output/scratch allocation, process/worker/runtime bootstrap and instrumentation setup precede the measured interval. Success, cancellation and a deliberate allocation control are separate processes. No performance timing or whole-program memory claim is made.

`run.py --output FRESH_DIRECTORY --scratch FRESH_SCRATCH_DIRECTORY` builds the executable with two Release compiler jobs, builds the interposer, extracts two existing synthetic fixtures, then executes the matrix. Both paths must be absent. The report binds sources, fixtures, commands and binary hashes. Existing evidence is never overwritten. A failed build stops the runner; an old executable is never accepted. Sanitizer builds must not be used for allocation counts.

The interposer covers malloc/calloc/realloc, aligned/valloc and malloc-zone entry points, plus mmap on the recorded host. The positive control must be observed. Zero counts describe these instrumented calls and supplied buffers for the measured path, not arbitrary callbacks or platform guarantees. Output samples, parser bounds, scalar failures, cancellation/lifetime and retained-arena semantics are independently tested in `Tests/SwiftJLITests/QualifiedJPEGTests.swift`.

The test-only C interposer is adapted from the pinned DICOMKit source and retains its MIT licence in `LICENSE.DICOMKit`; it is not part of the SwiftJLI library product.

For the separately retained mmap positive control, compile `calibrate_mmap.c` with `xcrun clang -Wall -Wextra -Werror -O2`, then invoke that executable with the generated `SCRATCH/libheap.dylib` as both its sole argument and `DYLD_INSERT_LIBRARIES`. It must report a positive mapping count and exit zero. This complements the runner's C and Swift allocation controls without executing a codec.
