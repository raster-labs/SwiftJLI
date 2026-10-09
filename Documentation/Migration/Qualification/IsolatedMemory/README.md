# Isolated-process memory comparison and attribution

Shipping source hashes identify 0a714f3; the predecessor remains pinned at
0a4ded0b0b2e8e38127f4f302b286e74ee352474. Native release builds use Swift 6.4,
`-gnone`, no sanitizer/tracing, macOS 27.0.1 ARM64. Each implementation/operation/
profile runs in a fresh process, with 25 operations and three interleaved process
repetitions. Five profiles at 512²/2048² give 120 measurements. SHA-256 output
checks match for every predecessor/successor pair. These are RSS measurements,
not latency results or a separation of all algorithm workspace allocations.

An initial harness copied its generated source into the successor owner but used
COW sharing for the predecessor. Its results are retained as setup diagnostics.
DirectInput corrects this by filling the successor allocation directly; no
shipping code changed. Generated JPEG inputs are reproducible with the retained
`prepare` command and their recorded hashes; those intermediate files are not
committed. Harness manifests retain the original sibling-checkout layout.

DirectInput measures 2048² RGB encode/decode peaks about 30–36% below the
predecessor. Greyscale and XYB large decode peaks rise by roughly the compressed
input size: the public Data API materialises a bounded array for native parsing.
Small-case RSS also includes the generic async executor and runtime allocations.
These costs must not be attributed to a decoded-image hand-off copy.

AttributionControls runs 54 additional fresh processes. The unmodified
predecessor is called through a generic async executor, then through that executor
with one deliberate compressed-input copy. All hashes still match. At 2048²,
median old-async-plus-copy versus successor decode RSS is 44.42 vs 44.73 MiB
(predictive16), 89.22 vs 89.42 MiB (DCT12), and 163.16 vs 163.47 MiB (XYB8).
At 512² XYB encode, the old async control rises to 30.88 MiB versus the successor's
31.17 MiB; the original synchronous predecessor is 26.59 MiB. Thus these outliers
have measured API/runtime attribution, rather than an unexplained image-copy
regression. Small differences must be read with the retained ranges.

The required asynchronous owning API and bounded compressed-input materialisation
are explicit migration trade-offs. The measured successor values form the
recorded memory baseline for these profiles. This is not a silent no-regression
claim: consumers must admit combined compressed input, destination, algorithm
workspace and concurrent work. Exact operation-report workspace peaks remain
unknown (`nil`); conservative admission reservations are not measured peaks.
Physical Watch resource qualification remains outstanding.
