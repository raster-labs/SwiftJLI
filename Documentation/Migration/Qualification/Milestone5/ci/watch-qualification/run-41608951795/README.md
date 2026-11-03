# Hosted runner capacity boundary

This record covers attempts 1 and 2 at the initial handoff. The owner later
requested a [single-job Watch retry, attempt 3](../watch-only-retry-20261103/README.md),
whose terminal outcome and source binding are retained separately.

[Run 41608951795](https://github.com/raster-labs/SwiftJLI/actions/runs/41608951795) targets head `07cc31e2f3eeb8e22cb12d1fe519e605ef5cffed`, merge `084bf719eb441477711de7226844901afd160749`, and the owner-confirmed pinned base `8ae2762710d6279cd92222f5bb5ca95f042f694e`. Its final status is **cancelled: seven carried successful jobs and six Apple jobs cancelled before execution**. **Fresh hosted execution of the corrected Watch verifier remains unexecuted.** No further retry or monitoring is active.

| Attempt | Outcome | Evidence |
| --- | --- | --- |
| 1 | Seven jobs pass. All six macOS ARM jobs fail to acquire a runner and are cancelled with zero steps. The workflow concludes `failure`. | [Run](attempt-1/workflow-run.json), [jobs](attempt-1/workflow-jobs.json), [raw capacity annotations](attempt-1/infrastructure/) |
| 2 | Exactly the six unexecuted Apple jobs are retried once. None acquires a runner or executes a step. An operator cancels the attempt after the agreed 15-minute acquisition bound; the workflow concludes `cancelled`. | [Terminal receipt](attempt-2/terminal-receipt.json), [run](attempt-2/workflow-run-terminal.json), [jobs](attempt-2/workflow-jobs-terminal.json), [raw annotations](attempt-2/infrastructure/) |

Attempt 1's annotations identify failure to acquire hosted runners and macOS ARM capacity constraints. The final SDK allocation terminated naturally before the cancellation preflight, so no cancellation request was sent for attempt 1. See the [retry preflight](retry-preflight.json). The seven successful jobs cover Linux Swift 6.2/6.4 on both architectures, native Intel, independent consumer resolution and shared contract identity. The [Intel receipt](attempt-1/macos-intel-log-receipt.json) and [raw log](attempt-1/macos-intel-job.log.gz) record 389 debug tests, 389 release tests and 250 CLI process checks.

The connected integration's [403 response](retry-request.json) created no retry. The authorised CLI request then succeeded:

```text
gh api --method POST repos/raster-labs/SwiftJLI/actions/runs/41608951795/rerun-failed-jobs
```

This uses GitHub's [failed-jobs-only endpoint](https://docs.github.com/en/rest/actions/workflow-runs#re-run-failed-jobs-from-a-workflow-run). The workflow has no dependency edges. The [accepted request](retry-cli-request.json) and [scope verification](attempt-2/scope-verification.json) identify all six new job IDs and prove that the seven successful jobs retained their original execution and step timestamps; they did not rerun.

At the retry bound, a [fresh preflight](attempt-2/bounded-cancel-preflight.json) found all six jobs still queued without runners or steps, after 921 seconds. The [operator cancellation request](attempt-2/bounded-cancel-request.json) records the exact command and reason. This second cancellation is an imposed waiting limit, not a second GitHub capacity-failure conclusion or a test failure.

The earlier [13/13 source qualification](../../test-isolation/README.md), [six passing hosted Watch Release cases](../run-41605599199/README.md), and [corrected verifier replay over that genuine artefact](../verifier-cache-fix/README.md) remain separate evidence. They do not convert this unavailable hosted verifier run into a pass. Qualification excludes the later `bbb0b1a` performance branch and does not establish physical Watch or system-RSS-ceiling acceptance.
