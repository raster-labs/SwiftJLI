# Rejected executable symbol-export experiment

Source baseline: `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8`; production sources are unchanged from round-four `0a8acd7`. Worktree `/private/tmp/swiftjli-round5-cli`, branch `codex/djpeg-round5-cli`.

The only experimental change was executable-target/macOS/release `-no_exported_symbols -dead_strip` through `Package.swift` linker settings. The installed Apple linker manual documents the former for executables without plug-ins and the latter for code unreachable from entry points/exported symbols. No dynamic plug-in loading was found in project source. Library-product settings, quality, format support, resource limits and compiler optimisation mode were unchanged.

`swift build -c release --jobs 4 --scratch-path /private/tmp/swiftjli-round5-cli-build --product swiftjli-cli` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` passed. The normal package build produced a binary of 1,215,664 bytes, versus 1,519,360 baseline bytes: 19.99% smaller. Exports fell from 1,810 to zero. Both binaries still had 21 linked-library load commands. See `build-manifest.json`, `build.log`, `package.patch`, and the exact segment/export/library text dumps.

`python3 benchmark.py` passed nine representative cases × two paired rounds. Every pair's full PNM output was byte-identical before timing. Each case used five warmups and twenty fresh-process observations per binary per round; every sample, p95, command and peak RSS is retained in `benchmark.json`. No per-round latency regression exceeded 5%, but no case improved more than 5% in both rounds either.

| Case | Mean round-median baseline → candidate ms | Time change | Peak RSS MiB |
|---|---:|---:|---:|
| flat-19 | 7.292 → 7.195 | −1.34% | 6.438 → 6.375 |
| flat-512 | 7.489 → 7.450 | −0.51% | 7.066 → 7.000 |
| ramp-19 | 7.467 → 7.360 | −1.44% | 6.438 → 6.375 |
| ramp-512 | 8.498 → 8.352 | −1.73% | 7.270 → 7.219 |
| noise-19 | 7.775 → 7.668 | −1.37% | 6.441 → 6.375 |
| noise-512 | 10.268 → 10.200 | −0.66% | 7.520 → 7.469 |
| mixed-19 | 7.675 → 7.739 | +0.83% | 6.438 → 6.375 |
| mixed-512 | 8.477 → 8.561 | +0.99% | 7.336 → 7.281 |
| dct12-512 | 9.599 → 9.470 | −1.34% | 8.188 → 8.109 |

Timings are diagnostic/provisional: AC power was present, but the VM used 79–103% CPU in the start/end snapshots and desktop workloads were active. No other SwiftJLI build/test/profile ran during this gate. This does not establish an accepted startup speed win or a win over djpeg. RSS fell only approximately 0.7–1.0% (typically 64 KiB).

Disposition: rejected; the small runtime benefit does not justify new manifest `unsafeFlags` and the accompanying independent-consumer qualification burden. Full CLI tests and external library-consumer acceptance were deliberately not run after the gain gate failed. `Package.swift` was restored exactly; the worktree is clean. Raw patch, executable hashes and failed-gain evidence remain available. No shipping production changes were made.
