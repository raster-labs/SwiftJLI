# Apple allocation/lifetime refresh — 3 November 2026

**Passed: 56 ordinary-build stress scopes and 56 deliberate retained-frame
controls.** This refresh exercises the current public decoder/execution paths
on native macOS with Apple allocator statistics. It is not a timing benchmark,
an independent JPEG oracle or physical-device qualification.

The repository revision at build start was
`f4e6e6562b32056affbb375f8cd6bb708bc7d8ad`. All 46 shipping Swift sources match
the previously recorded `5351088` source manifest and the Milestone 5 starting
candidate `8ae2762`. Source/harness hashes were unchanged across build and all
four executions; the executable hash was also unchanged. The exact working-tree
status, hashes, invocations and exit codes are in [results.json](results.json).

The build used Apple Swift **6.4.2** (`swiftlang-6.4.2.1.9`,
`clang-2100.4.1.1`), explicit **Swift Build**, release configuration and **two
jobs**, without sanitizers. The source package retains macOS deployment minimum
26.0. Exact host and Xcode identities are in [host.stdout](host.stdout) and
[xcode.stdout](xcode.stdout). A fresh build tree and executable remain under
`/private/tmp`; no production or harness source was edited.

## Executed matrix

Each of DCT12 greyscale and RGB8 covers 257² and 1024² samples, seven operation
categories, and batches of two or 32 operations. The categories are concurrent
encode/decode, invalid final UInt12 sample, encode/decode admission refusal and
encode/decode processing-callback cancellation. Each category receives five
warm-ups, with at most two operations in flight and two workers per operation.
Each batch joins before its ending allocator snapshot.

The four invocations are the ordinary binary, `--control-copy`, `--rgb8`, and
`--rgb8 --control-copy`. All exit zero and each emits exactly 28 records. The
supervisor independently verifies the complete matrix, expected outcomes,
profile, budgets and retention inequalities. Successful probe startup also
requires the harness's four-MiB allocation calibration to pass.

| Ordinary profile | Size | Maximum reported net live increase | One source frame |
| --- | --- | ---: | ---: |
| DCT12 | 257² | 0 bytes | 132,098 bytes |
| DCT12 | 1024² | 0 bytes | 2,097,152 bytes |
| RGB8 | 257² | 7,824 bytes | 198,147 bytes |
| RGB8 | 1024² | 0 bytes | 3,145,728 bytes |

Every ordinary scope remained below one full source frame. Every positive
control detected at least one deliberately retained complete source copy per
operation. Concurrent codestreams and decoded samples matched the same-build
reference, and failure/cancellation cases returned their required outcomes.
Raw [DCT12](dct12-baseline.stdout) and [RGB8](rgb8-baseline.stdout) measurements
and their [DCT12](dct12-control.stdout) / [RGB8](rgb8-control.stdout) controls are
retained without filtering.

## Measurement limits and reproduction

The explicit test budgets are one GiB algorithm workspace and two GiB total
operation memory, preserving the existing probe profile rather than changing
library defaults. Apple all-zone statistics include allocator rounding and
runtime allocations. Reported net increases are clipped at zero; zero is not
proof of zero allocations or leaks. All 112 zone high-water fields returned
zero and are treated as unavailable. Process RSS is cumulative for each
invocation, not per-operation workspace. Neither RSS nor these retained-frame
checks establishes a validated device memory ceiling, every copy shape or the
absence of smaller leaks. Callback cancellation does not measure mid-kernel
cancellation latency.

To reproduce from the repository root, choose a fresh output directory:

```sh
python3 Documentation/Migration/Qualification/Milestone5/apple-memory/run.py \
  --repository /Users/pushparaj/projects/SwiftJLI-milestone5 \
  --output /absolute/new/apple-memory-evidence
```

The supervisor builds the existing `Examples/AppleMemoryProbe` and runs all four
profiles. The current record is finite synthetic allocation/lifetime evidence;
other Milestone 5 release gates remain separate.
