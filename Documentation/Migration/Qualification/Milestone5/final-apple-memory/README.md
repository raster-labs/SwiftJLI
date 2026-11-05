# Final-candidate Apple allocation/lifetime refresh — 3 November 2026

**Passed: 56 ordinary-build stress scopes and 56 deliberate retained-frame
controls** at candidate `f548e5048e5c71204c2a2ec4036bf66c4f040285`.
All shipping and probe sources were checked against that immutable Git commit
before building, and source/binary hashes remained unchanged throughout the
four invocations. Exact commands, toolchain identity and hashes are retained in
[results.json](results.json).

The existing AppleMemoryProbe build cache was reused for an ordinary release
build with explicit Swift Build, Apple Swift 6.4.2 and two jobs, without
sanitizers. The source change was recompiled before execution. This is not a
clean-build or performance comparison. The 46 shipping sources include the new
`NativeExecution.swift` hash
`695d091246e8ed32a196d55e1722f08dcdf0785e579693963ce37df999b85d2e`;
the earlier candidate's memory receipts remain unchanged.

The unchanged probe covers DCT12 greyscale and RGB8, 257²/1024² samples, seven
operation categories and batches of two/32 operations. Categories are concurrent
encode/decode, invalid final UInt12 sample, encode/decode admission denial and
processing-callback cancellation. Five warm-ups precede each category, at most
two operations run concurrently, and each operation is limited to two workers.
The ordinary run and deliberate-copy control each emit 28 records per profile.
The supervisor checks complete matrix membership, expected outcomes and
retained-frame inequalities independently of the probe's assertions.

| Ordinary profile | Size | Maximum reported net live increase | One source frame |
| --- | --- | ---: | ---: |
| DCT12 | 257² | 0 bytes | 132,098 bytes |
| DCT12 | 1024² | 0 bytes | 2,097,152 bytes |
| RGB8 | 257² | 3,712 bytes | 198,147 bytes |
| RGB8 | 1024² | 0 bytes | 3,145,728 bytes |

Every ordinary scope retained less than a full source frame above its starting
live-allocation snapshot. All 56 positive controls detected at least the
deliberately retained source capacity for every operation. Concurrent outputs
match the same-build reference and all required failure/cancellation outcomes
pass. This is a retained-frame experiment, not an independent JPEG oracle or
proof against every copy shape or smaller leak.

The existing explicit probe budgets remain one GiB workspace and two GiB total
memory per operation; library defaults are unchanged. Net live increases are
clipped at zero, so zero does not imply zero allocations. All 112 allocator
high-water values returned zero and are unavailable; process RSS is cumulative,
not per-operation workspace. These figures do not establish physical-device
ceilings or mid-kernel cancellation latency. No timing measurements were taken.

To reproduce, choose a new evidence directory. Omit `--scratch` for a fresh build
tree, or explicitly provide an existing build cache as in the recorded run:

```sh
python3 Documentation/Migration/Qualification/Milestone5/final-apple-memory/run.py \
  --repository /absolute/SwiftJLI-checkout \
  --revision f548e5048e5c71204c2a2ec4036bf66c4f040285 \
  --output /absolute/new/final-apple-memory
```

The checkout must be at that revision and its source/harness bytes must match.
An existing result file is rejected before any build or probe execution.
