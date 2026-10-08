# Concurrent/failure memory qualification at shipping source 0a714f3

The shipping source hashes are recorded separately by each runner. Linux/glibc
passes 28 UInt12 stress scopes and 28 retained-frame controls. macOS ARM64 passes
56 scopes and 56 controls across UInt12 and RGB8, using automatic backend selection.
Both sizes (257² and 1024²) and batch counts (2 and 32) are represented. Each batch
has at most two in-flight operations, each capped at two workers. Success checks
retain exact encoded bytes and decoded samples. Invalid last-sample input,
admission denial and processing-callback cancellation must return their expected
errors; no success may be published. See the harness READMEs for precise scope.

The Linux source/destination allocation matrices are also refreshed: 30 encoder
and 60 decoder measurements, with the same numbers of deliberate-copy controls.
All pass without tracker overflow. Baseline source copies are absent from the
measured frame-size bins; decode allocation identity and padding checks pass.

Apple and Linux numbers have different meanings. Linux records requested heap
allocations within a scope. Apple reports allocator zone bytes in use and process
peak RSS; zero zone high-water values mean unavailable. Neither separates every
algorithm allocation from runtime overhead. These probes detect retained full
frames and their controls, not every small leak or copy. They do not inject actual
malloc failure into Swift's allocator or certify physical Watch memory ceilings.

A first RGB probe attempted the library default workspace budget and correctly
returned resourceLimitExceeded at 1024². Qualified runs explicitly request 1 GiB
workspace and 2 GiB total memory per operation, keeping admission defaults intact.
The predecessor-comparison and performance runs are separate, without allocation
instrumentation. The Apple runner copy is retained as a workspace reproduction
script; its workspace-relative paths are intentional.
