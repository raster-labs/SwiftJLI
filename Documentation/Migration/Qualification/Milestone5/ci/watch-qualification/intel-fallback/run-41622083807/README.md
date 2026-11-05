# Targeted Intel Watch qualification — passed

[Run 41622083807](https://github.com/raster-labs/SwiftJLI/actions/runs/41622083807)
passes its one executed Watch job at exact head
`8c1b9655319771d1fcaaa7f03c2d165ec3e7a333`. The seven other job definitions are
intentionally skipped without acquiring runners or executing steps. This manual
dispatch does not requalify those jobs; the earlier full matrix remains separate.
Monitoring has stopped. No further dispatch or retry was performed by this audit.

The [terminal receipt](terminal-receipt.json), [run metadata](workflow-run-terminal.json)
and [job steps](workflow-jobs-terminal.json) confirm:

- **389 library tests in 60 suites pass**, in Debug, with zero failed/skipped tests.
  The [raw library log](library/test.log.gz) and [xcresult summary](library-xcresult-summary.json)
  retain the count. The device-level counter reports 617 passed entries; it is
  preserved separately and is not added to the 389 top-level tests.
- **Six Release Watch qualification tests and six unique records pass**, with
  zero failed/skipped tests. The hosted [strict verifier receipt](watch/verification/receipt.json),
  [six records](watch/verification/watch-records.json), [result summary](watch/verification/xcresult-summary.json)
  and [raw harness log](watch/test.log.gz) retain the evidence.
- The actual host is **Intel x86_64, macOS 26.6.1**, image `20260824.0517.1`,
  **Xcode 26.6 / Apple Swift 6.3.3**. Both suites target the **watchOS 26.5
  simulator**, Apple Watch Ultra 3 (49mm), using the 26.5 SDK.
- All 49 package/shipping/harness source identities match the tested commit.
  [Source comparisons](source-binding.json) bind shipping code to `f548e50`,
  tests/examples to `a44e671`, and the simulator/verifier helpers to `07cc31e`.
- All **51 original harness xcresult files remain unchanged**. The verifier
  queries a verified copy; its only additional file is `database.sqlite3`.
  Input report/log hashes, command exits and the copy's 52 hashes also verify.

The complete [original uploaded ZIP](watchOS-runtime-evidence.zip) contains both
original xcresult bundles, the verifier's query copy and all uploaded logs.
Its SHA-256 matches GitHub's artefact digest:
`bd87cd83ccb3b1af70ed32d7fbfc5da261f56c6668f51eccaae47ac8938f64c0`.
The [download and 1,401-file manifest](artifact-download.json), [metadata](artifacts.json),
[complete job log](job.log.gz) and [log hashes](job-log-receipt.json) permit checking
the retained bytes. The library summary was read locally from a disposable
byte-verified copy; [its receipt](library-summary-read.json) proves the downloaded
original remained unchanged. No local codec test or simulator was executed.

The library step's buffered output took time to finish. One attempted partial-log
read returned 404; [that limitation](partial-log-read.json) remains recorded.
The existing timeout and checks were not weakened. Earlier ARM capacity failures
and the original verifier failure retain their separate unsuccessful results.
This pass qualifies simulator behaviour only: it establishes neither physical
Watch/iPhone/iPad qualification nor a system-RSS ceiling or controlled performance.
