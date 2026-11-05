# Owned-output result — 6e763ec

The fresh comparator build, current-candidate/libjpeg comparison, frozen-ca0 companion build and baseline/candidate RSS run all passed with exit0. Source is `6e763ec2099e162bae52a40109ff74269ea9899f`; baseline is `ca0c1e874177f429ed199f3ed8ef6ac1315ee66a`; libjpeg-turbo is the unchanged statically linked3.2.1 archive. Prepared receipt SHA256 is `99ff942a5d04aa19c4f409fabd91abeca34609d7ee53f195c47bac497d7b0586`; current executable SHA256 is `6851737841ac7edf8fa2fc9debce1ff8540f619d0c64c8ae7f5a7b8b9cc9ea9a`. All source, compiler, artifact, fixture, receipt and executable identities remained unchanged.

The four comparator implementation files remain byte-identical to qualified `c-final-5f9e1cf`. One full-output/every-sample quality preflight precedes each timing process; measured iterations check output edges after timing. The unchanged method uses5warm-ups and20samples per decoder in each of2rounds. FreshRSS uses3alternating-order pairs per admitted case, retaining compressed input and full output. Byte counts and complete-output FNV identities matched each process's expected output; no output copy was added.

There are **24 admitted timing records,8 named quality exclusions,72 current/C RSS records and72 fresh ca0/current RSS records**. Lossless differences are0; admitted DCT differences are at most1, within unchanged limits2/4. The four RGB/progressive512/2048 cases remain excluded at maximumdifference3>2 in both rounds. They have no latency or RSS win claim.

The shared host had an unrelated VM at 94.7–193.8%CPU across recorded snapshots, plus WindowServer activity. No other agent builds/tests/profiles overlapped this slot. Latencies remain provisional. Raw records include host/power/thermal snapshots and every command's stdout/stderr. This is the allocated-output API diagnostic, not default-admission or CLI qualification.

## Latency

Negative change means lower Swift median latency. Eleven of twelve admitted cases have lower medians in both rounds; the8-bit noise gap is only0.8–3.4% and should be treated as near parity. Single-worker2048DCT remains13.3–13.4%slower.

| Case (worker ceiling) | Swift ms, rounds1 /2 | C ms, rounds1 /2 | Swift change |
|---|---:|---:|---:|
| flat-19.jpg (w8) | 0.006938 / 0.007333 | 0.010750 / 0.010562 | -35.47% / -30.57% |
| ramp-19.jpg (w8) | 0.007250 / 0.008021 | 0.011291 / 0.011667 | -35.79% / -31.25% |
| noise-19.jpg (w8) | 0.007479 / 0.007896 | 0.011437 / 0.011709 | -34.61% / -32.56% |
| mixed-19.jpg (w8) | 0.007188 / 0.007146 | 0.010938 / 0.010958 | -34.29% / -34.79% |
| mixed-2048.jpg (w8) | 12.676541 / 12.715312 | 18.988563 / 19.072354 | -33.24% / -33.33% |
| dct12-512.jpg (w8) | 1.118626 / 1.161229 | 1.297624 / 1.326771 | -13.79% / -12.48% |
| dct12-2048.jpg (w8) | 15.898020 / 15.640709 | 19.388583 / 19.216583 | -18.00% / -18.61% |
| dct12-2048.jpg (w1) | 22.601937 / 22.131749 | 19.934521 / 19.536167 | +13.38% / +13.29% |
| flat-8-512.jpg (w8) | 0.053792 / 0.052417 | 0.076896 / 0.077562 | -30.05% / -32.42% |
| flat-12-512.jpg (w8) | 0.059313 / 0.060479 | 0.160750 / 0.171166 | -63.10% / -64.67% |
| noise-8-512.jpg (w8) | 1.089584 / 1.087625 | 1.098083 / 1.126146 | -0.77% / -3.42% |
| noise-12-512.jpg (w8) | 1.301479 / 1.295105 | 1.440104 / 1.358646 | -9.63% / -4.68% |

## Retained-output peak RSS

Values are median-of-three fresh-process peak RSS. The Swift/C columns come from the current common executable; the ca0/current columns come from a separate fresh pair series using identical comparator sources and the exact same compiled comparator C object. Small changes of one/few pages are not assigned a mechanism.

| Case (worker ceiling) | Swift / C MiB | Fresh ca0 /6e MiB | Fresh change KiB |
|---|---:|---:|---:|
| flat-19.jpg (w8) | 8.891 / 9.453 | 8.984 / 8.922 | -64 |
| ramp-19.jpg (w8) | 8.891 / 9.406 | 8.969 / 8.953 | -16 |
| noise-19.jpg (w8) | 8.891 / 9.406 | 8.984 / 8.953 | -32 |
| mixed-19.jpg (w8) | 8.922 / 9.406 | 8.953 / 8.938 | -16 |
| mixed-2048.jpg (w8) | 21.484 / 21.953 | 21.531 / 21.531 | +0 |
| dct12-512.jpg (w8) | 10.062 / 9.531 | 10.828 / 10.062 | -784 |
| dct12-2048.jpg (w8) | 20.469 / 19.953 | 21.219 / 20.484 | -752 |
| dct12-2048.jpg (w1) | 20.312 / 19.953 | 20.828 / 20.297 | -544 |
| flat-8-512.jpg (w8) | 9.297 / 8.984 | 9.297 / 9.344 | +48 |
| flat-12-512.jpg (w8) | 9.547 / 9.328 | 9.594 / 9.594 | +0 |
| noise-8-512.jpg (w8) | 9.797 / 9.188 | 10.516 / 9.828 | -704 |
| noise-12-512.jpg (w8) | 10.203 / 9.609 | 10.922 / 10.188 | -752 |

The comparison retains equal complete-output size, precision and lifetime on both sides; admitted dense/noise DCT pixel values differ by at most1 against C, so the two decoded byte sequences are not claimed identical.

All five admitted lossless cases have lower peakRSS than C. All seven admitted DCT cases remain0.219–0.609MiB above C. The fresh baseline pairs show roughly0.69–0.77MiB lower RSS for multi-worker denseDCT and0.53MiB for large single-workerDCT. Those are complete-candidate differences, not isolated attribution to one instruction or allocation. Explicit transformed-buffer payload fell768→128KiB for the pipeline and512→64KiB for one-worker reconstruction; allocator, stack and page residency are not inferred from that arithmetic.

All execution receipts are under `runs/initial`. `summary-rows.json` retains both timing rounds and all individual RSS samples. Earlier bbc preparation remains preserved and unexecuted; a metadata-preparation Python parse typo in this directory was retained separately and repaired before any codec execution. No comparator compile or runtime failure occurred in this run.

Remaining work: single-workerDCT latency, DCT memory versus C, excluded RGB quality and final product/CLI/platform gates. A separate diagnostic may inspect retained-output memory; it must not modify these official harness files, binaries or receipts.
