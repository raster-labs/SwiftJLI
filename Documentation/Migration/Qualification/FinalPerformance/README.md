# Final latency qualification — 8 October 2026

Shipping source is 0a714f32a2ef5e1b8be48f6b02500e43833489d2, byte-identical
under Sources at 7d85c34. Predecessor is unmodified JLISwift
0a4ded0b0b2e8e38127f4f302b286e74ee352474. Swift 6.4 native release builds
use `-gnone`, with no sanitizer or allocation tracing. Public measurements use
five warmups and twenty interleaved timed iterations. Source/binary hashes,
individual timing samples, output identity checks and commands are retained.
`status: passed` in runner manifests means the process and identity checks
passed; it does **not** mean the performance acceptance gate passed.

## Public results and disposition

Two 60-case expanded runs cover 19²/512²/2048²/3072², flat/ramp/noise, and
five profiles. All 120 codestream/sample comparisons pass exactly. Two ordinary
ten-case runs also pass all output comparisons. `per-case-summary.json` records
120 encode/decode combinations, each with two runs, absolute latency changes,
medians, observed ranges and approximate paired bootstrap intervals.

44 operation cases exceed 5% in both runs: 30 tiny 19² cases and 14 larger
cases. The tiny cases add approximately 1.7–13.8 microseconds. Repeated larger
increases include 512² flat/ramp RGB/progressive encoding (about 10–15%),
UInt12 flat/ramp encoding (about 5–17% across sizes), and large flat predictive
encoding (about 11–14%). Ordinary 512² progressive decode remains about
7–8% slower in both repeats. Consult individual records rather than treating
these ranges as every image's performance.

**PERF-03 remains open.** The measured successor values establish the candidate
baseline, not an approved blanket waiver. Investigations explain substantial
required safety/API costs, but residuals and borderline cases do not justify
an unconditional no-regression claim. Stable release needs either a demonstrated
fix or an explicit, evidence-backed disposition of the remaining regressions.

## Attribution, separated from acceptance measurements

- UInt12 and RGB private probes separate native work, operation context and
  checked borrowed-storage conversion. They localise overhead to context and
  checked input handling; the public wrapper contributes little in these probes.
- The required eight-worker default explains much of the large flat predictive
  cost: a sixteen-worker override improves those cases. It does not fix the
  progressive decode regression. The shipping default remains eight.
- A separate diagnostic checkout disables `NativeOperation.check()` only.
  Ordinary 512² progressive decode then measures +3.95%/+6.06%, versus
  +7.21%/+8.48% with shipping checks. This supports a contribution from required
  cancellation/deadline checks, not removal of those safeguards. The patch is
  retained solely for reproducing attribution and must never be shipped or
  used to qualify the library. Shipping source hashes retain the checks.
- Private `@testable` probes require `-enable-testing`, which changes code
  generation. Their timings do not override the public release comparisons or
  establish exact additive attribution across different executables.

## Environment and statistical limits

Native macOS 27.0.1 ARM64, Apple Swift 6.4 (swiftlang-6.4.0.34.1), sixteen
reported active processors. Expanded cases all report nominal thermal state
(0), and record system load. The power snapshot reports AC power with the
battery at 7% and discharging; a later observation showed charging. Stable power
conditions throughout cannot be claimed. Restricted sysctl queries and their
failures are preserved; the opaque battery identifier alone is redacted.
No inference of physical Watch or other-device latency is made.

Run `python3 summarise.py` to reproduce the summary. Each case/run uses a seeded
paired bootstrap of twenty interleaved predecessor/successor indices, 1,000
resamples and percentile endpoints, seed 6410. These approximate within-run
intervals do not account for machine-to-machine variance, temporal correlation
or multiple comparisons. Both raw runs and their ranges remain the primary
record; two process runs are not a broad population study.

## Reproduction

Restore `Harnesses/*` as sibling directories beside checkouts named `JLISwift`
and `SwiftJLI` at the revisions above, preserving their manifests. For public
results run:

```
swift build --package-path migration-benchmark-v2 --scratch-path build-public -c release -Xswiftc -gnone
build-public/release/Benchmark --extended
build-public/release/Benchmark
```

Run each twice without overlapping codec, fuzz or build work. Original runner
scripts retain exact absolute executable paths and arguments. Private
attribution packages build with the same flags plus `-Xswiftc -enable-testing`;
their product is `Attribution`. `public-workers16` is a public diagnostic with an
explicit caller override. For `public-check-control` only, create an isolated
copy named `SwiftJLI-check-final` from the shipping revision and apply
`git apply --unidiff-zero diagnostic-only-disabled-checks.patch`; never apply it
to the shipping checkout.
Do not compare sanitizer/traced binaries to these latency baselines.
