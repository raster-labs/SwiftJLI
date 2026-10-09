# UInt12 range-check attribution

The pre-change native/shared/public probe isolates the extra full-image
precision preflight. In two runs the public 1024² encode took 11.68–11.72 ms,
versus 10.82–10.85 ms for the predecessor. All produced identical codestreams.
The changed greyscale UInt12 DCT reader validates values while constructing its
required Float algorithm plane. Other reduced-precision inputs retain preflight,
including discarded alpha. Padding is not interpreted as samples.

Two subsequent public runs use five warm-ups and twenty interleaved timed
iterations, native release builds without sanitizers, on macOS ARM64. Exact
samples, codestreams, raw timings, thermal state and source hashes are retained.
These improve the UInt12 measurements but do not certify the entire performance
matrix. The progressive decode outlier remains subject to investigation.
The full Linux suite passes 342 tests in 49 suites; the live Apple predecessor
comparison matches all 71 records. Existing earlier evidence remains tied to its
own source hashes.
