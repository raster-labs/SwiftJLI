# Watch xcresult cache correction — genuine-artifact revalidation

**Passed:** the corrected helper accepts all six genuine Release Watch simulator
tests and six qualification records from run **41605599199**. This re-reads that
existing hosted artefact; it is not a new harness execution or a new hosted CI
pass. The original failed post-check remains in
[the run's retained evidence](../run-41605599199/).

The original helper hashed the bundle and then queried it in place. The summary
command added `database.sqlite3`, so the strict whole-bundle comparison failed
despite unchanged original result files. The independently retained
[cache reproduction](../run-41605599199/xcresult-cache-reproduction.json) identifies
that side effect. The corrected helper copies the bundle into its fresh
verification output, proves initial byte equality, and queries only that copy.
It records copy hashes and changes, allows only SQLite index/cache changes on
the copy, and continues to reject any original input mutation or copied result
payload change.

[The corrected receipt](verification/receipt.json) records six passed tests,
zero failed/skipped tests, six unique `watch-simulator` records, unchanged Watch
budget values, matching device/runtime, and all **49** package/shipping/harness
file identities. The isolated checkout is the exact CI merge
`c2de3838b750da0842af155d1c5ddd03c9232793`; only the corrected helper differs in
that checkout. The shipping source remains f548. [Checkout metadata](checkout.json)
and [execution/toolchain evidence](execution.json) retain the exact source,
helper hash, command, exit zero and local extraction tools.

Every file from the original CI bundle snapshot still has its recorded hash.
The downloaded artefact also contains the SQLite index created during the
original failed CI check. This pre-existing cache is preserved with the original
input, and the verified working copy is retained as `verification/SummaryInput.xcresult`.
No CoreSimulator service or local Watch harness was run for this revalidation.

[Mock fixture checks](../../../watch-verifier-tests/README.md) separately verify
copy-index acceptance and rejection of original/copy payload mutation, alongside
the earlier source, count, environment, version and budget guards. Hosted CI
must still validate the updated workflow. Simulator RSS and elapsed times do
not establish physical Watch memory ceilings or controlled performance.
