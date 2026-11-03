# macOS release crash — diagnosis and candidate correction

The original native macOS ARM64 and Intel release suites at PR #26 head `f4e6e6562b32056affbb375f8cd6bb708bc7d8ad` both fail on Apple Swift 6.3.3 / Xcode 26.6. Their retained OS crash reports identify the same failure: `EXC_BAD_ACCESS` / `SIGSEGV` at `0xfffffffffffffff8` while `swift_task_localValuePushImpl` pushes the optional throwing host callback in `NativeOperation.withSynchronousCancellation` (`NativeExecution.swift:50`). The calling test is `hostDeadlineAndMalformedCategoriesRemainDistinct` (`CLISynchronousExecutionTests.swift:111`), whose first callback immediately throws `CancellationError`. The last test name printed by concurrent stdout was not a reliable identification of the crashing test.

## Original failure evidence

[Workflow run 41596335122](https://github.com/raster-labs/SwiftJLI/actions/runs/41596335122) retains the failed qualification results. The original native release commands were unchanged; diagnostic runs did not replace their failure status.

| Architecture | Job | Artifact | Evidence |
| --- | --- | --- | --- |
| ARM64 | `125784455873` | `13212594039`, `macos-arm-release-evidence` | [Receipt](arm-receipt.json), [original OS crash report](arm-original-crash.ips.gz) |
| Intel | `125784455612` | `13211859328`, `macos-intel-release-evidence` | [Receipt](intel-receipt.json), [original OS crash report](intel-original-crash.ips.gz) |

The receipts include source revision, original artifact SHA-256, uncompressed crash-report SHA-256 and the triggered stack. [Before-fix hashes](before-callback-owner-fix.json) bind the exact implementation and regression source to those failures. No fixture payload or patient data was used.

The separately launched LLDB helper initially could not load `Testing.framework`; that loader failure is distinct from the original release crash. The diagnostic script now supplies the selected Xcode platform's `Developer/Library/Frameworks`, `Developer/Library/PrivateFrameworks` and `Developer/usr/lib` paths to the inferior, following [SwiftPM's testing environment setup](https://github.com/swiftlang/swift-package-manager/blob/e8e9677097acc3b0e9f0d6b217c8cd43a63d3ad4/Sources/Commands/Utilities/TestingSupport.swift#L347-L356) and [platform-path definitions](https://github.com/swiftlang/swift-package-manager/blob/e8e9677097acc3b0e9f0d6b217c8cd43a63d3ad4/Sources/PackageModel/SwiftSDKs/SwiftSDK.swift#L692-L709). Its corrected loader environment has not yet been exercised on the failing hosted toolchain in this checkpoint.

## Candidate correction and validation

The correction stores an immutable `Sendable` callback owner in the task local and in each captured operation context. The callback runs at the same entry, worker and completion boundaries; no cancellation check, error category or worker join is removed. This avoids using optional throwing-function metadata as the task-local value and makes retention explicit. The stack establishes the failure location; it does not independently establish an upstream compiler or runtime root cause.

The existing crashing test remains intact. A new nested-scope regression verifies that an immediately cancelled inner host scope never runs its body, restores the outer callback, and leaves later operations with neither completed callback. Existing regressions still exercise host callbacks outside a Swift task, task-cancellation inheritance, joined-worker release and codec output equivalence.

Fresh local release validation on Apple Swift 6.4.2 completed with **exit 0: 13 tests in two suites**. See the [exact command, compiler and before/after source hashes](callback-owner-swift642-release.json) and [complete log](callback-owner-swift642-release.log). `CLISynchronousExecutionTests` and `NativeExecutionTests` were selected in a fresh scratch directory with `-j 2`; this was not a benchmark. Shell syntax, embedded Python parsing and `git diff --check` also passed for the associated diagnostic change.

This local result is not a passing-after result on the failing Swift 6.3.3 runtime. Fresh hosted native ARM64/Intel release qualification remains required. The owner wrapper introduces one small object per synchronous host scope; its byte cost and performance impact are not measured here. The public asynchronous API and JPEG arithmetic are unchanged, but affected lifetime/security evidence and final-candidate campaigns must identify the new source separately from the earlier baseline.
