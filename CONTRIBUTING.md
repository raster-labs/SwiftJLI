# Contributing

Start with `AGENTS.md` and `IMPLEMENTATION.md`. The codec implementation is merged; the [acceptance ledger](Documentation/Migration/ACCEPTANCE.md) records maintenance changes and open qualification gates. Keep pull requests focused and preserve independent package consumption.

[MIGRATION.md](MIGRATION.md) guides application upgrades from JLISwift. Update its mappings, executable example and current-versus-planned status when changing the public API or qualifying a codec capability.

Every behavioural change needs relevant unit/regression tests. Parser or ownership changes need the matching security/lifetime checks; hot-path changes need controlled benchmark evidence. Public common API changes require the same contract revision in all four repositories and updated example/conformance tests. Codec-specific exceptions need an explicit reason.

New in-house contributions use Apache-2.0 with SPDX identifier Apache-2.0 where appropriate. Preserve accurate authorship and provenance. Declare third-party source/fixture/tool origins and licences; no unreviewed code import. Do not add private clinical data or secrets. British English is preferred for documentation.

PR descriptions state the problem, resulting behaviour, contract/source revisions, tests actually run, missing environments, memory/copy implications and measured performance where relevant. Do not copy predecessor success counts as successor evidence. Follow `SECURITY.md` for sensitive reports.
