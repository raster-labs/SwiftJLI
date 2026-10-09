# Apple memory stress probe

This standalone development consumer measures the same public-API workload as
AllocationProbe on macOS, using `malloc_zone_statistics(nil, ...)` and `getrusage`.
Build release and run `AppleMemoryProbe`, `--control-copy`, `--rgb8`, and
`--rgb8 --control-copy`. Each invocation covers 257²/1024² inputs, five warm-ups,
2/32 operations, at most two in-flight operations and two workers per operation.
The explicit per-operation ceilings are 1 GiB workspace and 2 GiB total memory;
the 1024² RGB conservative admission estimate exceeds the default workspace
ceiling. This is an explicitly enlarged test profile, not a changed library default.

Concurrent outputs, final-sample UInt12 rejection, encode/decode admission denial
and processing-callback cancellation are checked. Each operation is joined before
measurement ends. Cancellation does not claim a specific mid-kernel timing;
NativeExecutionTests separately verifies cancellation after actual worker entry.
The invalid-final-sample case always uses the UInt12 fixture, even in the RGB run.

A baseline batch must retain less than one full source frame above its starting
live allocation. Controls deliberately retain one whole source copy per operation
and must detect all of those bytes. These checks detect retained images; they do
not prove absence of smaller leaks, every copy shape or all failure modes.

Apple statistics include allocator rounding and process/runtime allocations;
they are not Linux requested-heap bins or pure algorithm workspace. The zone
high-water field can return zero (unavailable); process peak RSS is cumulative for
the invocation. Neither is an isolated per-operation workspace peak. Device memory
ceilings still require device evidence. Never compare these numbers as timings or
collect them under a sanitizer.
