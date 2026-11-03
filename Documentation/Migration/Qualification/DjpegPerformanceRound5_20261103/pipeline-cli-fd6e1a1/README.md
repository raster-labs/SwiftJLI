# Joined pipeline CLI benchmark follow-up — 3 November 2026

**The competitive goal remains open.** The accepted pipeline retains five unique large-lossless latency wins against both djpeg versions in both rounds. Small CLI latency, DCT512 latency and every accepted CLI peak-RSS case still favour djpeg. These are owner-authorised provisional timings under unrelated host work, with no overlapping local builds, profiling or tests.

Source `fd6e1a1530bf5584415aceef41125474ebfb26a3` has the same production sources as `14f3501`. The frozen CLI was built at production-equivalent `704ddae1bafea95d8a48c01ce35887c5b6413c0d`. Baseline is `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8` (round-four source). Suite policy 0.10.0, precision, resource defaults, platform floor and fixed quality gates are unchanged. See the [source/comment equivalence receipt](../pipeline-14f3501/source-pins.json) and [test-only correction](../experiments/ci-worker-failure/qualification.json).

All four benchmark commands exited0; exact commands, timestamps and host load are in [cli-benchmark-commands.json](cli-benchmark-commands.json). Each accepted case uses five warmups and20 samples in each of two order-balanced rounds. Timing includes process launch, input read, decoding and full PNM output to `/dev/null`. Peak RSS is whole-process resident memory. The Swift CLI retains a complete decoded image, while djpeg can emit scanlines; this is the actual CLI comparison, distinct from the [equivalent owned-output API comparison](../pipeline-14f3501/README.md). No memory win is inferred from the API diagnostic.

Every accepted baseline/candidate PNM and sample comparison is exact. Fixed djpeg gates remain0 for lossless,2 for8-bit DCT and4 for12-bit DCT. Original RGB/progressive512 exceed the existing gate (maximum difference3 versus tolerance2) and remain excluded. Noise2048/3072 and mixed3072 are rejected by both Swift CLIs under unchanged default memory limits (exit5), so have no accepted timing. The `lossless16-2048` fixture aliases `mixed-2048`; it is not a sixth independent win.

Tables show the mean of the two per-round medians. Positive reduction means SwiftJLI is faster; both round values are retained. RSS likewise averages the two per-round medians. Raw samples, per-round RSS and executable/input/output hashes are in the linked original JSON files.

## djpeg 3.2.1

[Original matrix](cli-original-3.2.1.json) · [Expanded lossless matrix](cli-lossless-patterns-3.2.1.json)

| Case | Swift ms | djpeg ms | Reduction, rounds1/2 | Swift/djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| lossless16 512² | 9.150 | 7.498 | -23.5% / -20.7% | 7.332 / 2.812 |
| lossless16 2048² | 23.605 | 28.710 | +17.7% / +17.9% | 19.078 / 2.844 |
| dct12 512² | 9.875 | 7.757 | -27.9% / -26.7% | 8.398 / 2.203 |
| flat 19² | 8.317 | 6.342 | -34.3% / -28.7% | 6.438 / 2.750 |
| flat 512² | 8.658 | 7.514 | -14.5% / -15.8% | 7.047 / 2.812 |
| flat 2048² | 10.822 | 20.812 | +49.1% / +47.0% | 15.000 / 2.844 |
| flat 3072² | 14.198 | 38.166 | +64.1% / +61.5% | 25.633 / 2.844 |
| ramp 19² | 8.833 | 7.029 | -27.4% / -24.1% | 6.438 / 2.750 |
| ramp 512² | 10.038 | 8.319 | -21.5% / -19.8% | 7.250 / 2.812 |
| ramp 2048² | 21.811 | 27.490 | +21.6% / +19.8% | 17.578 / 2.844 |
| ramp 3072² | 36.296 | 50.954 | +28.3% / +29.3% | 30.188 / 2.844 |
| noise 19² | 9.152 | 7.134 | -27.5% / -29.1% | 6.438 / 2.750 |
| noise 512² | 11.915 | 8.932 | -32.9% / -33.9% | 7.520 / 2.812 |
| mixed 19² | 9.224 | 7.168 | -31.0% / -26.5% | 6.438 / 2.750 |
| mixed 512² | 10.250 | 8.860 | -13.3% / -18.1% | 7.328 / 2.812 |
| mixed 2048² | 24.113 | 28.995 | +16.7% / +17.0% | 19.074 / 2.844 |

## djpeg 3.2.0

[Original matrix](cli-original-3.2.0.json) · [Expanded lossless matrix](cli-lossless-patterns-3.2.0.json)

| Case | Swift ms | djpeg ms | Reduction, rounds1/2 | Swift/djpeg RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| lossless16 512² | 8.952 | 7.356 | -21.7% / -21.7% | 7.328 / 2.812 |
| lossless16 2048² | 23.237 | 28.105 | +17.8% / +16.9% | 19.078 / 2.844 |
| dct12 512² | 10.130 | 7.766 | -30.5% / -30.3% | 8.344 / 2.203 |
| flat 19² | 8.452 | 6.235 | -38.0% / -33.6% | 6.438 / 2.734 |
| flat 512² | 8.519 | 7.037 | -25.9% / -17.2% | 7.047 / 2.812 |
| flat 2048² | 11.288 | 18.935 | +41.5% / +39.3% | 15.008 / 2.844 |
| flat 3072² | 14.561 | 32.560 | +56.1% / +54.4% | 25.633 / 2.844 |
| ramp 19² | 9.002 | 6.911 | -30.9% / -29.6% | 6.438 / 2.734 |
| ramp 512² | 9.880 | 8.171 | -21.6% / -20.2% | 7.250 / 2.812 |
| ramp 2048² | 21.768 | 27.181 | +20.3% / +19.5% | 17.570 / 2.844 |
| ramp 3072² | 36.346 | 51.071 | +29.9% / +27.7% | 30.195 / 2.844 |
| noise 19² | 9.274 | 7.198 | -29.4% / -28.3% | 6.438 / 2.734 |
| noise 512² | 11.198 | 8.435 | -34.0% / -31.6% | 7.500 / 2.812 |
| mixed 19² | 9.160 | 7.144 | -25.7% / -30.7% | 6.438 / 2.734 |
| mixed 512² | 10.328 | 8.549 | -20.9% / -20.7% | 7.328 / 2.812 |
| mixed 2048² | 24.601 | 29.611 | +17.1% / +16.7% | 19.078 / 2.844 |

The retained earlier f4 CLI measurements remain a separate checkpoint. These later measurements do not establish controlled final acceptance or change any quality exclusion. [Archive manifest](manifest.json) records byte-identical original receipts.

The corrected worker-failure test passes all four Linux CI jobs (Swift6.2/6.4 on x86_64/ARM64) in [run41663076174](https://github.com/raster-labs/SwiftJLI/actions/runs/41663076174). At this [captured snapshot](ci-fd6-latest.json), native Intel was still running and six Apple ARM jobs were queued. This does not close final-platform qualification.
