# Watch verifier fixtures — no simulator execution

[The current fixture run](attempt-3/report.json) passes **one positive and 27 negative
mock record/summary cases**, one positive and three negative source-identity
fixtures, plus rejection of an existing output directory without changing its
sentinel. These are Python acceptance-check fixtures. They establish no
Watch simulator, physical-device, memory-ceiling or codec test result.

The negative fixtures cover missing/duplicate/unknown records, host and physical
environments, failed/skipped overall and per-device xcresult summaries, a
mismatched device or OS version, an old runtime, missing/failed command exits, Debug selection,
incorrect counts, each of the six Watch budget fields, and non-finite timing.
They exercise the production verifier's pure validation function; they do not
substitute a mock `xcresulttool` into the hosted workflow.

The production [verifier](../../../../../Scripts/verify-watch-qualification.py)
extracts an actual xcresult summary with a bounded subprocess, requires six
successful Release simulator tests and six matching records, and retains input,
source, bundle and helper hashes. It checks root package, shipping and harness
bytes against the Git revision; same-HEAD dirty bytes and missing tracked source
are rejected. Hosted CI must execute the harness and pass
that verifier before simulator qualification can be claimed. Physical-device
qualification remains separate.

Reproduce these fixtures with a new output directory:

```sh
python3 Documentation/Migration/Qualification/Milestone5/watch-verifier-tests/run.py \
  --repository /absolute/SwiftJLI-checkout --output /absolute/new/watch-verifier-fixtures
```

Helper and fixture-runner SHA-256 values are recorded in the result. The separate
[local preflight](../watch-simulator-preflight/README.md) records why no local
Watch tests were executed.

The summary field shape follows the real retained [visionOS xcresult summary](../ci/test-isolation/visionos-xcresult-summary.json); its exact SHA-256 is recorded in the fixture receipt. Watch devices, counts and records here are explicitly synthetic. Earlier fixture attempts remain retained with their executed helper hashes.
