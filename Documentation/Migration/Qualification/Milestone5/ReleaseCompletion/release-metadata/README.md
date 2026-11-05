# Prepared 1.1.0 CLI metadata — 4 November 2026

**Local metadata/CLI checks passed; stable publication remains pending.** VERSION,
the CLI, its manual and current guides now agree on `1.1.0`. Library implementation
and the package manifest still match qualified source
`f548e5048e5c71204c2a2ec4036bf66c4f040285`. The containing commit will identify the
new metadata source; [report.json](report.json) hashes the exact edited files.

On Xcode 27.2 / Apple Swift 6.4.2, the explicit Swift Build Release CLI build and
all **250 process checks** passed. This includes help/version, payloads, limits,
errors, pipes, staged installation and matching rendered manual checks. No
library hot path, fidelity rule or resource default changed; no new performance
or physical-device claim is made. The installer used temporary staging only.

The exact absolute argv, selected developer directory, times, zero top-level
exit codes and binary hash are in [report.json](report.json). Individual expected
CLI outcomes are in [cli/report.json](cli/report.json); some negative cases
intentionally return their documented nonzero status.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  build --build-system swiftbuild --disable-sandbox --jobs 2 \
  --configuration release --product swiftjli-cli
python3 Scripts/test-cli.py --binary <built-release-executable> --output <fresh-evidence-directory>
```

Physical Watch/iPhone/iPad qualification, consumer migration, final source-bound
SBOMs and versioned URL resolution remain required before publishing the stable
release. These local checks are not a stable tag or a new hosted-matrix result.
