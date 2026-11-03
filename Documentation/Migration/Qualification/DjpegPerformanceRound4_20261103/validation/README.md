# Round 4 validation evidence — 3 November 2026

This archive separates the executed source trees. Suite policy **0.10.0**, the Swift 6.2 manifest minimum and Apple OS 26.0 deployment floor remain unchanged.

- Earlier local validation: `82d4b25510daceeddb40d1a2395e683203d76526`.
- Final source: `0a8acd72ddeac6fb1911457ae28b689eef0e9db1`.
- Prior checkpoint with failed native macOS CI: `8ae2762710d6279cd92222f5bb5ca95f042f694e`.

Some local tests executed the working tree immediately before its listed commit; the executing agent confirmed the source mapping and command receipts. [Source manifest](../source-manifest.json) hashes 171 tracked files under Sources, Tests, Scripts, `.github/workflows` and `Package.swift` directly from the final Git revision.

| Source | Check | Recorded result | Evidence |
|---|---|---|---|
| `82d4b25` | Full Release | 403 tests / 63 suites passed | [Log](release-tests.log) |
| `82d4b25` | Full AddressSanitizer | 403 tests / 63 suites passed | [Log](asan-tests.log) |
| `82d4b25` | Focused ThreadSanitizer | 67 tests / 14 suites passed | [Log](tsan-tests.log) |
| `82d4b25` | Release CLI | 252 process checks passed | [Log](release-cli-final.log), [command report](release-cli-report.json) |
| `82d4b25` | AddressSanitizer CLI | 252 process checks passed | [Log](asan-cli.log), [command report](asan-cli-report.json) |
| `82d4b25` | Lossless oracle | 210 profiles passed both directions; exact declared point-transform samples | [Log](lossless-oracle.log) |
| `82d4b25` | DCT oracle | 48 profiles passed both directions; maximum sample difference 2 | [Log](dct-oracle.log) |
| `82d4b25` | Shared contract hashes | All seven documents matched | [Log](contract-hashes.log) |
| `0a8acd7` | Full Release | 403 tests / 63 suites passed | [Log](final-release-tests.log) |
| `0a8acd7` | Focused AddressSanitizer | 23 tests / 4 suites passed | [Log](final-asan-followup.log) |
| `0a8acd7` | Focused ThreadSanitizer | 23 tests / 4 suites passed | [Log](final-tsan-followup.log) |

Every listed local command exited 0. Counts use Swift Testing's final summaries, not parameter-case expansion or the preceding XCTest summary of zero tests. Full ASan, CLI and oracle results belong to the earlier pin; the final source received the explicitly listed follow-ups. The oracle used libjpeg-turbo **3.2.1 (build 20261026)**. DCT tolerances remained 2 samples for 8-bit and 4 for 12-bit. [Oracle JSON](oracle-summary.json) is explicitly derived from the logs; the original oracle scripts do not emit JSON summaries.

The local working directory was `/private/tmp/swiftjli-djpeg-round4`, with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and no `ASAN_OPTIONS` override. [Additional command receipts](additional-validation-commands.json) preserve the five full/final test invocations, source mapping and exit statuses. Their commands were:

```sh
swift test -c release --jobs 4 --scratch-path /private/tmp/swiftjli-round4-build
swift test --jobs 4 --scratch-path /private/tmp/swiftjli-round4-asan --sanitize address
swift test --jobs 4 --scratch-path /private/tmp/swiftjli-round4-asan --sanitize address --filter 'StreamingWorkspaceAdmissionTests|BoundedDCTWorkspaceTests|CompressedInputOwnershipTests|NativeExecutionTests|CancellationPublicationTests'
swift test --jobs 4 --scratch-path /private/tmp/swiftjli-round4-tsan --sanitize thread --filter 'StreamingWorkspaceAdmissionTests|BoundedDCTWorkspaceTests|CompressedInputOwnershipTests|NativeExecutionTests|CancellationPublicationTests'
```

The full Release command ran at both source trees. [Original validation JSON](validation.json) retains the exact CLI, earlier TSan, oracle and contract commands, timestamps and exit statuses. [Runner](run-validation.py) and [runner log](validation-run.log) are unchanged copies; the runner contains the historical temporary paths.

Failed evidence is retained separately under `failures/`. The [Intel CI log](failures/baseline-ci/baseline-ci-0.log) and [ARM64 CI log](failures/baseline-ci/baseline-ci-1.log) record successful 388-test Debug runs followed by Release runtime signal 11 and command exit 1 at `8ae2762`, using Apple Swift 6.3.3 / Xcode 26.6. Neither contains a crash stack. Local passes do not resolve these failures or establish final-source CI acceptance. The final workflow adds crash-artifact retention without changing the failing test commands.

The [initial input-owner build](failures/development/data-reader-tests.log) failed because test call sites still passed arrays to the new byte-owner API. The [initial admission-test build](failures/development/streaming-admission-tests.log) failed because a throwing `#require` argument lacked `try`. These are intermediate uncommitted-tree compilation failures, not final-source passes; no exact immutable source pins were retained for them.

Only text logs, JSON reports and the validation runner are archived here. No generated image fixtures or executables are included. [Evidence manifest](evidence-manifest.json) records file sizes, line counts and SHA-256 hashes.
