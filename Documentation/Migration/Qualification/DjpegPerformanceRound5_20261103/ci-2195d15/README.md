# Remote CI follow-up for integrated source 2195d15

[Run 41710047213](https://github.com/raster-labs/SwiftJLI/actions/runs/41710047213) completed with failure on source `2195d15e05ab2359a19e635d8a83d440b7dea7ba`, whose 186 source/test/package files match locally qualified `6e763ec2099e162bae52a40109ff74269ea9899f`. Suite policy remains 0.10.0.

The native Intel macOS job passed Debug, then aborted during Release with `freed pointer was not the last allocation`. The crash stack reaches `swift_task_dealloc`, specialised `TaskLocal.withValue`, and `CACPublicPipelineTests.publicDecodePreservesRestartCrossingAndCallerPadding` at line 72. The reported host is x86_64 macOS 26.6.1, using Xcode 26.6. The CLI installation step was skipped. The failure is reproduced and a test-only correction has passed the focused local ARM64 gate; native Intel verification remains pending. This failure is not waived as host noise or overwritten by local ARM64 results.

Four Linux jobs passed: Swift 6.2 and 6.4 on x86_64 and ARM64. The independent tools-6.2 consumer and shared-contract byte-identity job also passed. Six Apple SDK/simulator/ARM jobs were cancelled without executing steps. These are unavailable gates, not passed tests.

Evidence was retrieved with `gh run view 41710047213 --log-failed` and `gh run view 41710047213 --json status,conclusion,jobs,headSha,url`; both retrieval commands exited 0. The job statuses and failed log are retained byte-for-byte. No workflow rerun or test exclusion was requested. The earlier local ARM64 results remain valid for their recorded source and environment, but cross-platform acceptance is open.

The [test-only helper correction](helper-correction/RESULTS.md), tested at `2436f95b4dd8a83d1513c2837cb99f280494bfdb` and integrated as `6b18817`, preserves all 16 parameter cases and assertions. The retained failing Intel binary reproduces the exact abort under local Rosetta; the candidate passes ARM64 Release. This is not yet a native Intel correction pass. The initial launcher failure and emitted-code analysis correction remain retained. No production code changed, so the prior production benchmark results retain their original source pins.
