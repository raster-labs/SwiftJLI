# Non-Watch migration qualification — 12 October 2026

This record qualifies the shipping source at `e7e54f756cccec07a66870ebefd68b5bbb5c79a6`
(the decoder corrections are unchanged from `ba39fda`). Source hashes accompany
the campaigns; subsequent changes in this task are development harnesses,
evidence and documentation. Original migration provenance remains pinned to
JLISwift `0a4ded0b0b2e8e38127f4f302b286e74ee352474`. Performance and isolated-memory
comparisons use corrected predecessor v0.5.2,
`981da4efb7d62e4370c5d6de706d56a729b9552e`, so both sides reconstruct the same
centred chroma samples. That comparison pin does not replace original provenance.
Common suite policy remains 0.10.0 and the seven supplied documents are unchanged.

Physical Watch testing is excluded. On 13 October 2026 the owner also deferred
private-reporting activation to a later administrator task; both remain
stable-release prerequisites. Watch simulator
qualification remains required. This work does not publish a release, retire the
predecessor or cut over an application. The current acceptance decision is in
[the ledger](../../ACCEPTANCE.md); historical evidence is not rewritten.

The initial owner follow-up still reported battery power and discharging;
`power-followup.json` preserves that observation. After the owner checked the
charger, macOS recognised AC power and all four comparisons were rerun successfully.
The AC baseline below supplements the retained battery measurements. CI [38253517616](https://github.com/raster-labs/SwiftJLI/actions/runs/38253517616)
subsequently passed all 13 jobs at qualification commit `2c45328`; its check
summary is retained in `ci/qualification-commit-checks.json`.

## Platform and source identity

[CI 38241825202](https://github.com/raster-labs/SwiftJLI/actions/runs/38241825202)
passes all 13 jobs for PR head e7e54f7. GitHub checked out synthetic merge
`5079cb7288365a09736a59a90c7273c3b35981b8`; Sources, Tests, Package.swift,
Scripts and workflows are byte-identical to that head. Linux Swift 6.2/6.4 on
ARM64/x86_64 each pass 349 tests in debug and release. Native macOS ARM/Intel
pass 354 tests; macOS ARM also passes separate ASan and TSan suites. Linux 6.4
and Intel CLI checks each pass all 107 process/install/manual checks. iOS,
tvOS, visionOS and watchOS simulators each pass 354 tests; iOS
also runs both pinned predecessor comparisons. SDK compilation and the tools-6.2
independent consumer pass. Job logs and simulator reports are retained under
`ci/`, including the exact simulator runtimes and test counts. This does not
supply physical Watch resource evidence.

## Full-hour decoder fuzzing

All four independent campaigns ran for at least 3,600 seconds and exited zero:

| Entry | Attempts | Accepted | Rejected | Peak process RSS bytes |
| --- | ---: | ---: | ---: | ---: |
| inspect | 582,782,583 | 215,269,677 | 367,512,906 | 24,313,856 |
| inspectJPEG | 583,266,684 | 215,448,603 | 367,818,081 | 24,379,392 |
| allocate | 72,260,264 | 18,575,018 | 53,685,246 | 26,165,248 |
| destination | 67,025,469 | 17,211,676 | 49,813,793 | 26,075,136 |

No unresolved crash, hang, watchdog or bounds finding occurred. Source hashes
and the executed binary hash were rechecked after completion. Each Linux process
was limited to one CPU and 256 MiB, with a 30-second progress watchdog. This is
deterministic release mutation, not coverage-guided or sanitizer fuzzing.
Inspection acceptance does not certify entropy validity; accepted full decodes
are counted separately. Raw completion records and compressed progress logs are
under `fuzz/`. Timing campaigns start only after all four processes stop.

## Completed independent and memory checks

- DCT: 48 profiles in both oracle directions, maximum difference two original
  sample units; established limits are two for 8-bit and four for 12-bit.
- Predictive JPEG: 210 precision/predictor/point-transform cases in both
  directions, every sample exact.
- Raw RGB: 16 independent 8/12-bit sequential/progressive, scalar/automatic and
  allocating/padded-destination combinations; maximum difference one sample
  unit. Caller allocation identity, prefix and row padding are preserved.
- Linux allocator: 60 decode and 30 encode scopes, each with matching deliberate
  full-frame-copy controls. Failure/cancellation stress adds 28 scopes and 28
  retained-frame controls. All interposer calibrations pass without overflow.
- Apple failure/cancellation stress: 56 scopes and 56 retained-frame controls.
  This is allocation/lifetime evidence, separate from sanitizer measurements.
- Isolated memory: 120 fresh-process comparisons, three repetitions of five
  profiles at 512²/2048², encode/decode, 25 operations per process. All output
  hashes match the corrected predecessor. Fifty-four additional controls
  separate required asynchronous execution and compressed-input materialisation.
  `memory-summary.json` records medians and observed ranges, not just ratios.
- Suite integration: all six codec pairs in both directions, six 12/16-bit cases
  each: 72 handoffs, 72 independent decodes, 72 allocator scopes and 72 copy
  controls. Native ASan and TSan each pass all 72 handoffs. Tracing permits only
  72 final compressed-file writes and the harness executable. See the
  [harness contract and reproduction](../../../../Examples/SuitePairIntegration/README.md).
- All 28 actual shared documents match at the four refreshed peer pins.
  A fresh remote-URL consumer at e7e54f7 passes predictive, progressive, float,
  XYB, RGBA, YCbCr and greyscale conversion profiles.
- Build-associated CycloneDX 1.7 validates. Raw SPDX 3.0.1 still fails the
  independent versioned schema on two producer records (`externalUrl` and
  `software_internalVersion`). Raw output and exact errors are retained; the
  toolchain discrepancy is reported as required by PLATFORMS, not patched out.

The memory increases above 5% are investigated explicitly. At 512²,
lossless16 encode rises 6.17% (14,598,144 to 15,499,264 median RSS bytes); the
required asynchronous API control leaves 4.99%. Lossless16 decode rises 31.57%
at 512² and 12.2% at 2048²; asynchronous execution plus bounded compressed-input
materialisation leaves approximately 2.1% and 0.6%, respectively. These are
whole-process peaks, not pure workspace. The trade-off retains the required
executor/cancellation lifecycle and bounded native parser input. The measured
successor medians/ranges establish the memory baseline; no extra handoff image
is permitted or observed in the independent allocation controls. No unsupported
claim that `peakWorkspaceBytes` is measured is made: the public field remains
unknown and reservations remain conservative admission bounds.

## AC-powered performance follow-up — 13 October 2026

The same public release binary and harness ran at repository revision `b6ac50e93999dad52a54637008e452961e3376cf`.
Shipping source hashes match the previously qualified e7e54f7 source; binary,
harness and source hashes were verified before and after execution. Corrected
predecessor v0.5.2 (`981da4e`) and original migration provenance remain unchanged.
Two expanded 60-case and two ordinary ten-case runs retain five warm-ups and
twenty interleaved observations per implementation. All **140 output comparisons**
match exactly. The 140 distinct encode/decode operation cases are each measured
twice. All case thermal states are nominal; 66 in-run power snapshots plus the
initial/final snapshots record AC power with unchanged settings. The owner
confirmed heavy applications were idle; no local codec build, fuzzing, sanitizer
or tracing overlapped the timings.

**43 operation cases exceed 5% in both runs; 97 do not.** Each repeated increase
has an explicit measured safety/correctness disposition and successor baseline in
[performance-ac/disposition.json](performance-ac/disposition.json).

| Accepted cost group | Cases | Observed repeated increases | Retained reason |
| --- | ---: | --- | --- |
| Tiny 19×19 images | 30 | 7.05–256.58%; **1.04–22.54 μs** | Checked admission, validation, bounded execution, cancellation and owning publication. |
| Larger UInt12 DCT encodes | 9 | 5.03–17.86%; **0.18–5.87 ms** | Checked strided input reads, meaningful-precision validation and row cancellation into the required algorithm plane. |
| 512² RGB/sequential-progressive encodes | 4 | 9.36–17.76%; **0.17–0.31 ms** | Direct borrowed RGB reads, bounded conversion scratch, joined workers and cancellation. |

Compared with the battery assessment, three additional cases repeat above 5%:
19×19 noise lossless16 encode (1.04–1.50 μs), 19×19 noise RGB encode
(8.96–11.00 μs), and 3072² noise UInt12 encode (5.31–5.87 ms).
They execute the same already investigated fixed-overhead and checked-loader
paths. Their individual measurements and approximate paired bootstrap intervals
are retained; the two-run threshold rule is not a population-significance claim.
Earlier native/context/shared/public attribution probes cover identical shipping
source and remain diagnostic evidence. They were collected during battery
qualification: their private `@testable` timings are not AC timings and are not
added to the public measurements. No unexplained confirmed case remains in this
finite matrix; no safety guard or fidelity limit was relaxed.

The AC results establish a separate current successor baseline for AC operation.
The battery assessment below remains intact with its own 40 repeated crossings;
the datasets are not pooled. This is one developer host and does not establish
universal no-regression or cross-device performance. Raw samples, per-case
medians/ranges, power records, command exits and archive hashes are under
`performance-ac/`. Reproduction uses `run-completion-performance-ac.py`,
`summarise-completion-performance-ac.py` and `record-ac-disposition.py` with fresh
output paths; the scripts retain the qualification host paths and pinned inputs.

## Retained battery latency disposition and baseline

PERF-03 is qualified for this representative matrix with **explicit measured
safety/correctness trade-offs**, not a claim of zero regressions. Two expanded
60-case and two ordinary ten-case runs preserve every one of the 140 output
comparisons. There are 140 distinct encode/decode operation cases, each measured
twice with five warm-ups and twenty interleaved observations per implementation.
Forty cross 5% in both repeats; the other 100 do not cross it repeatedly.

| Accepted cost group | Cases | Observed repeated increases | Retained reason |
| --- | ---: | --- | --- |
| Tiny 19×19 images | 28 | 7.99–248.09%; **1.46–23.21 μs** | Checked admission/metadata/parsing, bounded native decode, asynchronous execution, cancellation/deadline checks and owning publication dominate very small payloads. |
| Larger UInt12 DCT encodes | 8 | 5.29–15.99%; **0.17–4.25 ms** | Fused strided little-endian reads validate meaningful precision while writing the required algorithm plane, with row cancellation. No extra packed source image is introduced. |
| 512² RGB/sequential-progressive encodes | 4 | 7.60–12.16%; **0.13–0.19 ms** | Direct borrowed input, eight-row conversion scratch, bounded joined workers and cancellation. Sequential/progressive paths share this input conversion. |

[performance/disposition.json](performance/disposition.json) contains a decision
for every operation case, both measured costs and ranges, approximate paired
bootstrap intervals, diagnostic/source references, and the **new successor
baseline**. Every repeated crossing is explicitly accepted for its stated
reason and measured scope. No unexplained confirmed crossing remains in this
matrix. This decision follows the owner's request to complete migration and
PERF-03's documented trade-off rule; it is not a silent blanket waiver, stable
release approval or a promise for unmeasured workloads.

Two independent repetitions of native/context/shared/public encoder probes
localise the larger costs. UInt12 public and shared paths are close, while
context and checked loading account for the extra work. The RGB probes show
both bounded context and row conversion costs. Additional 19×19 decode probes
cover all five profiles twice with exact samples: validated parsing takes
about 4.1–14.4 μs and the public boundary adds admission/lifetime work beyond
bare decoding. Those diagnostic timings use different `@testable` code generation
and are **not additive** to public release timings. The original private DCT
borrowed-destination probe is not applicable to SOF3; its failed extension is
retained explicitly, and the corrected diagnostic uses full/native/public
SOF3 paths. Public decode/storage tests were not skipped or weakened.

All 140 public comparisons report nominal thermal state. Sixty-six power
snapshots retain the same normal battery power/settings throughout; AC power
is not claimed. No local fuzzing, codec build, sanitizer or tracing overlapped
the public timings; raw per-case load averages remain recorded. This is one
controlled developer host, not a cross-device population study. Approximate
bootstrap intervals describe within-run sampling, with no independence,
multiple-comparison or machine-to-machine confidence guarantee.

The earlier 16–21% advisory chroma cost compared correct reconstruction with
the former incorrect path. The corrected output is required and its component
planes are necessary algorithm workspace. The controlled baseline here uses
fixed predecessor v0.5.2 and therefore compares identical outputs. Original
provenance and earlier measurements remain intact; this record does not claim
that correcting chroma has no cost versus the old output.

## Outstanding administrative and excluded work

The supported-version policy is in SECURITY.md. Private vulnerability reporting
is still disabled; activation returned HTTP 404 and the connected account has
push access without admin permission. A repository administrator must enable it
or supply an established private contact. The prepared advisory link is not
advertised as active. On 13 October 2026 the owner deferred this administrative
action to a later task. It remains a prerequisite before stable release; it is
not an unfinished action assigned to this follow-up. The original API result is
preserved in `private-reporting.json`; `owner-disposition.json` records the deferral.

Physical Watch testing is excluded by the owner and remains unexecuted.
JLIDICOM/JLIBench products and CLI payload verbs retain the explicit I1–I3
deferrals; stable publication and downstream cutover remain separate tasks.
The known raw SPDX generator/schema discrepancy is recorded above as required
by the platform contract, not hidden behind a JSON-parsing success.

## Reproduction and evidence boundaries

From the SwiftJLI checkout, use fresh output and scratch directories:

```sh
python3 Scripts/verify-dct-interop.py --output-dir /new/dct --scratch-path /new/oracle-build
python3 Scripts/verify-lossless-interop.py --output-dir /new/lossless --scratch-path /new/oracle-build
python3 Scripts/verify-raw-rgb-interop.py --output-dir /new/raw-rgb --scratch-path /new/oracle-build
python3 Scripts/run-allocation-probe.py --operation decode --output-dir /new/decode
python3 Scripts/run-allocation-probe.py --operation encode --output-dir /new/encode
python3 Scripts/run-allocation-probe.py --operation stress --output-dir /new/stress
python3 Scripts/run-decoder-fuzz.py --output-dir /new/fuzz
```

The retained supervisors contain the exact executed argument arrays, environment
checks and exit codes. Their absolute paths describe the qualification host;
restore the archived harness directories as siblings of pinned SwiftJLI and
JLISwift-fixed checkouts and adjust those paths for reproduction. Public timings
use release `-gnone` builds without sanitizers, tracing or coverage. Diagnostic
`@testable` builds use `-enable-testing`; their timings cannot be added to or
substituted for the public measurements.

The oracle image contains CharLS 2.4.2 and libjxl 0.7.0. For JPEG, the host uses
libjpeg-turbo 3.2.0 rather than Ubuntu's older JPEG tool. The libjxl 12-bit PNM
normalisation is explicitly checked and exactly inverted; see the suite harness
README. No oracle becomes a shipping dependency or runs within a handoff.

Initial development attempts correctly failed on mutable-owner access, reuse of
a consumed destination lease, an unspecified SwiftJXL report field, merged
stdout/stderr telemetry and the external decoder's PNM representation. The
corrected harness reuses the reserved destination, retains sealed readers,
keeps unknown counters unknown, separates streams and verifies exact original
sample recovery. These were harness issues, not waived codec failures. The
allocator verifier also rejects a deliberately altered extra-allocation record;
that negative verifier check is distinguished from an executed codec mutant.

Compressed logs preserve their uncompressed hashes in `archive-manifest.json`.
Large generated pixel files and executables are not duplicated in Git; generators,
commands, binary hashes and fixture hashes identify the reproducible evidence.
Finite synthetic matrices, deterministic mutation and measured allocation shapes
do not constitute universal JPEG conformance, exhaustive fault injection or
security certification. Physical Watch behaviour remains unexecuted.
