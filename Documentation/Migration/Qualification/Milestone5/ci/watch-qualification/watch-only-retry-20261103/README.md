# User-requested Watch-only ARM retry

The user explicitly requested another attempt at the remaining hosted Watch verification. One **single-job** retry was made in [run 41608951795](https://github.com/raster-labs/SwiftJLI/actions/runs/41608951795), creating attempt **3**, Watch job **125865284797**. GitHub cancelled it before execution because no hosted macOS ARM runner was acquired. The job has **zero steps and runner ID 0**; the workflow concludes `failure`. **The corrected Watch verifier remains unexecuted in this ARM attempt.** Monitoring has stopped, with no additional retry from this task.

The [preflight](preflight.json) binds the request to documentation head `8d0f8b4cbb3c482376e88caa8b6e894f3042a75d`, original workflow head `07cc31e2f3eeb8e22cb12d1fe519e605ef5cffed`, merge `084bf719eb441477711de7226844901afd160749`, and pinned base `8ae2762710d6279cd92222f5bb5ca95f042f694e`. At request time, source, tests, helpers, examples, manifest and workflow bytes matched the original run; shipping source matched frozen candidate `f548e5048e5c71204c2a2ec4036bf66c4f040285`.

The connected integration returned [403 without creating an attempt](connector-request.json). After verifying that attempt 2 remained terminal, the authorised CLI fallback succeeded:

```text
gh api --method POST repos/raster-labs/SwiftJLI/actions/jobs/125838931961/rerun
```

The [accepted request](cli-request.json) records 10:36:27.630922 UTC and a 15-minute acquisition bound ending at 10:51:27.630922 UTC. The [scope verification](scope-verification.json) confirms that only Watch was retried: seven prior successful jobs and five prior cancellations were carried forward. Successful-job step timestamps remained identical. GitHub regenerated `started_at` metadata for carried cancellation records while retaining their old completion times and zero steps; those records are not fresh executions.

At the bound preflight, Watch had already terminated naturally with GitHub's runner-acquisition failure and capacity notices. The [guard](bounded-cancel-preflight.json) therefore sent **no operator cancellation request**. The [terminal receipt](terminal-receipt.json), [raw job](watch-job-terminal.json), [annotations](watch-annotations-terminal.json) and [complete attempt job list](workflow-jobs-terminal.json) preserve that outcome.

The [source post-check](source-postcheck.json) confirms unchanged shipping code, tests' qualification basis and helpers. Root's separate workflow change for an Intel Watch dispatch does not alter this ARM run's source binding; its result belongs to separate evidence. No source, helper or workflow file was edited by this monitoring task, and this attempt provides no new simulator, physical-device or RSS-ceiling qualification.
