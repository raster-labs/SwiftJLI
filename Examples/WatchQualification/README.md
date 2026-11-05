# Physical Watch qualification harness

Development-only Swift Testing package for the remaining Milestone 4 device
gate (TEST-06, PLAT-01). It is outside the shipping dependency graph. It uses
the public API and the existing `ResourceLimits.watch` without raising budgets.
No physical Watch result is claimed by the presence of this package.

Six serial tests cover:

- The Watch defaults and descriptor-only decoded-size boundaries below, at and
  above 32 MiB, without allocating those boundary images.
- Sixteen 12/16-bit lossless round trips into padded caller storage, exact
  deterministic sample expectations, unchanged encoded bytes, allocation
  identity, copy reports and rejection of a second writer.
- Eight encodes using at most two simultaneous readers, with joined tasks.
- 8/12-bit greyscale/RGB sequential/progressive DCT under every advertised
  backend with Watch budgets. This checks resource behaviour and output
  descriptors, not independent DCT fidelity; the repository's oracle evidence
  remains the fidelity gate.
- A 1024×513 input that fits decoded storage but exceeds the conservative
  encoder workspace reservation, followed by a successful smaller operation.
- Eight processing-callback cancellations, encode/decode deadline rejection
  with a deliberately shortened deadline, and recovery under normal limits.

Each completed case prints a `WATCH_QUALIFICATION` JSON record containing the
environment, OS, budgets, elapsed wall time and process peak RSS. A test-runner
failure or assertion failure invalidates the run even if records were printed.
The six expected case names are fixed in the test source.

## Validate the harness on a Mac

From the repository root:

```sh
swift test --package-path Examples/WatchQualification --disable-xctest -j 2
swift test --package-path Examples/WatchQualification -c release --disable-xctest -j 2
```

These records say `host-harness-check`. Watch simulator records say
`watch-simulator`. Neither closes physical-device qualification. A Watch SDK
compile proves compilation only. Do not use sanitizer RSS as device memory
evidence.

## Physical device procedure — unexecuted

Connect a developer-enabled, paired Watch running watchOS 26 or later. From
`Examples/WatchQualification`, discover the actual destination and scheme:

```sh
xcodebuild -list -json
xcodebuild -showdestinations -scheme WatchQualification-Package
```

Use the **physical watchOS** destination identifier, with the developer's actual
signing team. The following is a command template, not executed device evidence:

```sh
xcodebuild test -scheme WatchQualification-Package -configuration Release \
  -destination 'platform=watchOS,id=PHYSICAL_WATCH_DESTINATION_ID' \
  -destination-timeout 120 -parallel-testing-enabled NO \
  -resultBundlePath /absolute/new/watch-qualification.xcresult \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID > /absolute/new/watch-qualification.log 2>&1
```

Retain the command's actual exit status. Signing or destination failure is a
failed setup, not a test pass; never substitute a simulator. Signing and running
this package on a physical Watch have not yet been verified. If the device's
Xcode test runner requires an application host, add and qualify that host before
claiming this command works on hardware.

Record the source commit and clean/dirty status, hashes of this harness and
shipping sources, Xcode/compiler/SDK versions, exact Watch model and OS build,
power/thermal conditions, invocation, exit code, full log and xcresult. Require
six passing tests, zero failures/skips and six records whose environment is
`physical-watch`. Review the actual numbers; a passing test count alone does
not establish safe device ceilings.

Repeat ordinary and failure workloads on the target device, inspect retained
memory after joined work using device tooling, and investigate crashes,
termination, increasing retained memory or unacceptable latency. These small
fixtures do not exhaust every resource ceiling, prove all allocation failures,
or qualify every supported profile at its maximum admitted size. Expand the
measured workload if device results expose a risk. Existing full oracle, fuzz,
allocator and worker-cancellation evidence remains separately pinned.

RSS includes the test runner and runtime and is a cumulative process high-water
mark, not per-operation workspace. The 64 MiB budget is an operation admission
ceiling, not an assertion that total process RSS stays below 64 MiB. Two small
concurrent operations do not establish process-wide admission for arbitrary
concurrency. Deadline measurements include test/setup overhead; callback
cancellation does not establish mid-kernel cancellation latency.

Any necessary default adjustment requires a coordinated shared-contract
revision and requalification. After reviewing real device evidence, update
the Milestone 4 record and acceptance ledger. Milestone 5 remains a separate
release task.
