# Deadline overflow correction — 9 October 2026

Review of cf3cf5f reproduced a SIGTRAP with a deadline accepted by the public
ResourceLimits initializer: Double.greatestFiniteMagnitude. NativeOperation.check
converted this finite value to Duration and overflowed its internal integer.
The same empty input with a normal deadline returned malformedInput.

The corrected check converts elapsed Duration components to Double seconds and
compares them against the caller's deadline. It does not construct a Duration
from the caller value or cap the accepted deadline. Task and worker cancellation
checks remain in place. The public API and common contracts are unchanged.

The native release reproducer now returns malformedInput with exit 0 for both
normal and maximum finite deadlines. Linux Swift 6.4 release passes 344 tests
in 49 suites. NativeExecutionTests adds normal/huge finite deadline public
encode, inspect, inspectJPEG and both decode paths; a fractional expired deadline;
and dispatch-worker cancellation/joining with the maximum finite deadline.

Commands executed from the workspace root:

```
docker run --rm -v "$PWD/work/SwiftJLI:/repo:ro" -v "$PWD/work/build-deadline-linux:/build" -w /repo swift:6.4-noble swift test --scratch-path /build -c release
CLANG_MODULE_CACHE_PATH="$PWD/work/review-module-cache" swift build --package-path work/review-deadline --scratch-path work/build-review-deadline --disable-sandbox -c release -Xswiftc -gnone
work/build-review-deadline/release/Review --normal
work/build-review-deadline/release/Review
```

The standalone reproduction imports SwiftJLI from the adjacent source package;
reproduction.swift is its executable source. Before/after results retain the
process exits and diagnostic text. The after build is identified by source hashes.

Two native release benchmark runs use the existing migration-benchmark-v2 harness
retained under FinalPerformance/Harnesses, five warmups and twenty interleaved
iterations per case. All twenty public output comparisons pass. Raw per-case
samples are retained; this focused check does not close the prior expanded
performance gate or replace physical Watch qualification. The earlier full CI,
fuzz and broad qualification records remain evidence for their recorded source
revisions, not unexecuted claims about this change. PR CI reruns for the fix.
