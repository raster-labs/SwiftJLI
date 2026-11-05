# Diagnostic comparison with equivalent full-output ownership

This is a development-only harness, not a new SwiftJLI dependency or codec fallback. It does not replace the djpeg CLI benchmark or complete the optimisation goal.

The shared executable contains SwiftJLI production source from `0a8acd72ddeac6fb1911457ae28b689eef0e9db1` (identical production source at documentation checkpoint `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8`) and the pinned Homebrew libjpeg-turbo 3.2.1 static archive. Both engine modes therefore have identical executable/runtime mappings. The archive is linked by its absolute Cellar path, avoiding a mutable dynamic install-name lookup. `build.json` pins sources, headers, compiler, library object, archive, output binary and exact commands.

Important hashes:

- SwiftJLI object: `c98eeb52d679a6879d84dc91ce1ca313e89d2dc003e70e5f666f2c16f436e9cf`.
- libjpeg archive: `6442fb105eea6691a2e1eec07b21ab49c65d8813eff22791a6f204f264e914ef`.
- Shared executable: `132a7ab9d7251c941ac12d8d60ea2475d66721d4849167f9bdf207e194eb31f3`.

## Method and limits

Compressed `Data` is retained, and both paths allocate and retain the complete decoded output. The C shim uses `calloc`, checked geometry and bounded arrays of 16 row pointers. It selects the declared 8-, 12- or 16-bit scanline API, accurate integer IDCT, full resolution and matching greyscale/RGB output. There is no sample reduction or scanline discard. The C `setjmp`/`longjmp` boundary remains wholly inside one synchronous C call; mutable error/cleanup state is heap-owned. Input pointers remain inside the `Data.withUnsafeBytes` borrow through finish and decoder destruction. The returned output has one owner and an explicit free.

Timings cover state/workspace/full-output allocation through decode completion and return. Checksum access and output destruction occur outside the interval. Swift uses its public allocating async API on the generic executor; libjpeg is single-threaded internally. The Swift worker ceiling is recorded for every case. Both full outputs exist simultaneously only during the separate, untimed quality gate, which compares every sample. Full-output FNV-1a checksums aid cross-process identity; they are not used in place of sample comparison. The in-process timing harness is not used to claim peak memory.

Separate fresh-process memory modes retain compressed input and one complete final output, compute a full-output checksum without allocating a verification copy, and record Darwin `time -l` peak RSS. Three balanced paired trials per case. Swift explicitly permits 8 GiB workspace / 10 GiB total for this expanded probe; the C shim sets its memory manager's workspace envelope to 8 GiB and bounds fixture dimensions/output to 8192 / 512 MiB. No product default is raised. These are whole-process RSS values, not codec-only allocation telemetry.

`python3 build.py` and `python3 run.py` exited 0. All 105 child invocations exited 0: one contained-error process, 32 timing/quality processes and 72 memory processes. Four malformed inputs, including missing final EOI, were caught within C. Twelve case/worker configurations passed both quality rounds; four RGB/progressive configurations were excluded in both rounds at maximum difference 3, above the unchanged tolerance 2. Lossless required exact samples; admitted DCT cases observed differences 0–1, within fixed 8-bit/12-bit tolerances 2/4.

The local static libjpeg archive contains objects built for macOS 27.0. Linking the diagnostic at a 26.0 target produced the warnings preserved in `build-1.log`; execution was on macOS 27.0.1. This is not OS 26 qualification and does not change the shipping deployment floor. No ASan/TSan or cross-platform qualification of this development shim was executed. Independent source review found no actionable lifetime, overflow or timing-boundary issue.

## Provisional timing observations

Five warmups and twenty individual paired observations per engine, with alternating order; two rounds. Values below are means of the round medians. Negative time change means SwiftJLI is faster. **All observations are provisional**: recorded snapshots show VM activity around 110–150% CPU, an independent `npm install` around 340–427%, and FSEvents around 109–163%. No other SwiftJLI build/test/profile overlapped. DCT12-2048 with eight workers illustrates the host variation: first-round Swift/C medians were 46.794/33.001 ms, second-round 25.420/18.803 ms.

| Case | Workers | Swift ms | libjpeg ms | Swift time change vs C | Swift / C median RSS MiB |
|---|---:|---:|---:|---:|---:|
| flat-19 | 8 | 0.009729 | 0.010458 | −6.97% | 8.8125 / 9.2969 |
| ramp-19 | 8 | 0.010083 | 0.011458 | −12.00% | 8.7500 / 9.2656 |
| noise-19 | 8 | 0.010458 | 0.011521 | −9.22% | 8.7969 / 9.2656 |
| mixed-19 | 8 | 0.010031 | 0.011177 | −10.25% | 8.7656 / 9.2969 |
| mixed-2048 | 8 | 12.658448 | 18.997562 | −33.37% | 21.3281 / 21.7969 |
| dct12-512 | 8 | 1.748854 | 1.178562 | +48.39% | 10.4531 / 9.4062 |
| dct12-2048 | 8 | 36.106896 | 25.902198 | +39.40% | 56.3906 / 19.8281 |
| dct12-2048 | 1 | 28.069917 | 19.033823 | +47.47% | 20.8750 / 19.8438 |
| flat-8-512 | 8 | 0.499938 | 0.078656 | +535.60% | 10.0156 / 8.8594 |
| flat-12-512 | 8 | 0.508781 | 0.160208 | +217.57% | 10.2344 / 9.2031 |
| noise-8-512 | 8 | 1.644094 | 1.017396 | +61.60% | 10.2188 / 9.0625 |
| noise-12-512 | 8 | 2.077979 | 1.318115 | +57.65% | 10.6250 / 9.5469 |

Only ramp19, mixed19 and mixed2048 are numerically more than 5% faster in both rounds. Flat19's first-round reduction and noise19's second-round reduction were each 4.83%. No result is promoted to an accepted speed win under host contention. Tiny lossless RSS is about 5.1–5.7% lower in this shared executable/full-output lifecycle; that is not a CLI RSS win. DCT12-2048's one-worker RSS is 5.2% above the equivalent C path, while eight-worker RSS remains 184.4% above it.

The remaining DCT target is particularly clear for flat 8-bit and 12-bit images, where Swift took about 6.36× and 3.18× the C API time respectively. The production CLI comparisons and their startup/scanline-memory gaps remain unchanged.

`results.json` retains every sample, p95, exclusion, fresh-process RSS, host snapshot, command and exit status. Do not overwrite this baseline directory when testing a new candidate: copy the source files to a new evidence directory, then run `build.py --products <candidate-products> --source-revision <exact-pin>` there and run its `run.py` separately.
