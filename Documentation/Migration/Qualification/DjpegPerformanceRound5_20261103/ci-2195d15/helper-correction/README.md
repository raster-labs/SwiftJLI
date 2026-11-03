# Intel Release TaskLocal preflight diagnostic

This is a prepared diagnostic, not a passed correction. Candidate `2436f95b4dd8a83d1513c2837cb99f280494bfdb` changes only `CACPublicPipelineTests.swift` from selected `2195d15e05ab2359a19e635d8a83d440b7dea7ba`. It moves the same TaskLocal metadata preflight into a private synchronous, non-inlined helper. All 16 cases and the public decoding, padding, fidelity, copy and storage-lifetime assertions remain.

The CI failure reports `freed pointer was not the last allocation` in `swift_task_dealloc`, inlined `TaskLocal.withValue`, before either public async decode. This is consistent with a task allocation cleanup ordering problem in the test's generated async frame. Compiler attribution remains a hypothesis. It is different from the earlier null-metadata failure; the nominal cancellation callback wrapper remains unchanged.

`source-review.json` separates facts and hypotheses. `prepared.json` pins the failed bundle, compiler, local Testing framework, source and runner. `Entrypoint.swift` is byte-identical to official SwiftPM's `swift-6.3-RELEASE` helper (Git blob `93d27cb70de00c15e708ab2533fcbf74160cdb7a`); its copyright and Apache-2.0 with Runtime Library Exception notice remain verbatim. This diagnostic does not introduce a shipping dependency.

After an explicit parent CPU grant, run serially from this directory:

```sh
python3 run.py build-helper --run initial --execute --cpu-grant '<actual parent grant>'
python3 run.py retained --run initial --execute --cpu-grant '<actual parent grant>'
python3 run.py focused --run initial --execute --cpu-grant '<actual parent grant>'
```

Every action preserves its command, log, exit status and input/output hashes. A repeated action requires a new run name. A retained test crash is evidence, not a passed test. If the retained bundle cannot load because its original resource bundle is absent, retain that failure before preparing a separately labelled resource setup attempt. Do not silently retry or modify the retained binary.

The retained Intel binary was built by CI Xcode 26.6 and ran there on native x86_64 macOS 26.6.1. The local diagnostic uses Rosetta, the local macOS 27 host and Xcode 27.2 / Swift 6.4.2 runtime/frameworks. A local reproduction can confirm the old binary's failure site in that environment; it does not reproduce the original host/runtime. The candidate focused run is local ARM64 Release. Actual native Intel acceptance requires follow-up CI with the unchanged test coverage.
