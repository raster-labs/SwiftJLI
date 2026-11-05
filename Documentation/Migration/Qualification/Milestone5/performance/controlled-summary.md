# Callback-owner incremental performance assessment

**Accepted for the scoped PERF-03 regression comparison.** The matched run has no above-5% median-latency or maximum-observed-peak-RSS increase in either of two interleaved rounds. This is a before/after check of the callback-owner correction on one ARM64 Mac, with ordinary desktop load; it is not an exclusive-host measurement, a universal speed claim or a new complete predecessor matrix.

The [raw result](controlled/results.json), [executed runner](controlled/run-executed.py) and [independently recalculated disposition](controlled-disposition.json) retain all 24 rows, 960 timed subprocesses and raw samples. There were also 240 warmups and 48 output-validation subprocesses: 1,248 commands total. All 24 baseline/candidate output comparisons performed before timing were byte-exact; timed outputs were sent to `/dev/null` and were not compared individually.

Baseline source is `8ae2762710d6279cd92222f5bb5ca95f042f694e`; candidate shipping source is `f548e5048e5c71204c2a2ec4036bf66c4f040285`. The measurement checkout was `1f6f5a132f656bb2babdab52c94f7c711d7e1fd3`, with the same candidate source manifest. [Matched build metadata](matched-builds.json) records Apple Swift 6.4.2, Release product builds, identical normalised build requests, and executable hashes. Only `NativeExecution.swift` differs in shipping source.

All 96 retained latency/RSS distributions and 48 throughput values were independently recalculated from samples. The executed helper, provenance, build receipt, binary and 46 current source hashes match the run. Median uses the middle-pair mean; p95 is sample 19 of 20. The JSON reports each distribution’s minimum, maximum and median absolute deviation. No formal confidence interval or statistically significant speed gain is asserted.

| Candidate change across 24 round/case/operation rows | Minimum | Maximum |
| --- | ---: | ---: |
| Median latency | -3.372% | +1.334% |
| p95 latency | -5.735% | +45.113% |
| Maximum latency | -21.950% | +114.054% |
| Median of per-process peak RSS | -1.458% | +0.360% |
| p95 of per-process peak RSS | -4.324% | +3.176% |
| Maximum observed per-process peak RSS | -3.448% | +3.003% |

The worst median-latency increase is flat-19 decode round 2: 7.740021 → 7.843250 ms (+0.103229 ms, +1.334%). The worst maximum-peak-RSS increase is RGB8 encode round 1: 18,006,016 → 18,546,688 bytes (+540,672 bytes, +3.003%). Applying the 5% memory threshold to the maximum observed peaks, as well as reporting medians, avoids hiding a peak behind an average.

| Case | Operation | Median latency change, rounds 1 / 2 | Maximum peak RSS change, rounds 1 / 2 |
| --- | --- | ---: | ---: |
| lossless16-512 | decode | +1.208% / -1.308% | -0.587% / +0.994% |
| lossless16-512 | encode | -2.903% / -1.744% | -0.275% / -0.963% |
| lossless16-2048 | decode | +0.018% / -0.199% | -0.111% / -0.056% |
| lossless16-2048 | encode | -2.215% / -3.372% | -0.137% / -0.046% |
| dct12-512 | decode | -2.063% / -1.324% | -0.130% / -0.261% |
| dct12-512 | encode | -0.288% / -0.215% | -2.993% / -0.333% |
| rgb8-512 | decode | -2.358% / -2.750% | +0.091% / -0.452% |
| rgb8-512 | encode | -0.751% / -0.485% | +3.003% / -1.613% |
| progressiveRGB8-512 | decode | +0.571% / +0.649% | +0.352% / -0.609% |
| progressiveRGB8-512 | encode | -1.367% / -0.432% | -0.452% / -3.448% |
| flat-19 | decode | -0.190% / +1.334% | -0.241% / -0.241% |
| flat-19 | encode | -2.903% / -0.692% | -0.477% / +0.000% |

Latency tails are noisy. Five p95 comparisons cross +5% in one round: lossless16-512 decode (+8.371%), DCT12 encode (+5.159%), progressive RGB encode (+21.053%), flat-19 decode (+45.113%) in round 1, and lossless16-2048 encode (+9.722%) in round 2. None of these p95 crossings repeats for the same case in the other round. The flat-19 round-1 maximum is 8.661416 → 18.540084 ms (+114.054%); its median changes −0.190%. Lossless16-512 decode maximum latency also rises in both rounds (+17.385% / +12.542%), while its median changes +1.208% / −1.308% and p95 +8.371% / +0.418%. These observations prevent a tail-latency claim; maximum latency is not the PERF-03 median-latency statistic.

The host ran macOS 27.0.1 (26A434), ARM64, Apple Swift 6.4.2. Both snapshots show AC power at 100% charged and no recorded thermal/performance warning. No continuous thermal trace was recorded. Codec benchmarks, fuzz campaigns and build jobs had ended, and none appears as a competing job in the endpoint process snapshots. Those snapshots do not prove absence of all activity throughout the run.

The desktop was active: WebKit GPU CPU snapshots were 98.8% → 100.0%, WindowServer 73.4% → 73.5%, and the virtual-machine process 75.8% → 18.8%. Other desktop services were present. The 23.089-second window and falling VM snapshot mean residual contention and drift cannot be excluded. Adjacent baseline/candidate execution, alternating which runs first on every iteration, five warmups, twenty samples and a reversed-order second round reduce order bias. They support this finite incremental regression check without establishing a fully idle or exclusive host.

Under [PERF-03](../../../../PERFORMANCE.md), reproducible median-latency or peak-memory increases above 5% require investigation. Neither statistic crosses that threshold here in either round, so the observed results do not require another benchmark round to close this scoped correction’s gate. The small changes remain within the observed spread; they are not established improvements. A quieter repeated run would be needed for stronger kernel-cost, tail-latency or tiny-speedup claims, or if subsequent measurements produce a repeatable threshold crossing. No benchmark was rerun as part of this independent analysis.

Elapsed time includes Python launch/wait, `/usr/bin/time -l`, input reads, codec work and output to `/dev/null`; tiny cases are dominated in part by process overhead. RSS is the per-process lifetime maximum, not isolated algorithm workspace or an allocation/copy count. Separate allocation and lifetime qualification supplies those facts. Both binaries used identical options; progressive encode explicitly used successive approximation. Exact output equality also establishes unchanged encoded size for this matrix. Independent oracle bounds, historical RGB tolerance-2 timing exclusions, the excluded loaded run, physical-device qualification and the wider release gates remain separate.
