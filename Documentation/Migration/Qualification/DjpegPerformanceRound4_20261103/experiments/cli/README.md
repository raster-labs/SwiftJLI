# SwiftJLI round 4 CLI investigation

Baseline source: `8ae2762710d6279cd92222f5bb5ca95f042f694e` (production code `5351088d3bb4630a32de6509e4d62210ad14aaa0`). Suite policy 0.10.0. No public API, fidelity, admission ceilings or cancellation policy changes. Local macOS qualification only.

Candidate commit: `ae70b432574ffddd53c5d9d57d09202812fe355e`. Candidate source is in `/private/tmp/swiftjli-round4-cli`, branch `codex/djpeg-round4-cli`. Both uninstrumented executables were compiled with identical release flags against the same qualified baseline `SwiftJLI.o`. The separate instrumented executable is diagnostic only and is never used for accepted benchmark comparisons.

Changes:

- For a regular input that ends at its `fstat` size hint, probe EOF with one stack byte. Avoid the previously unconditional 64 KiB fallback allocation. Changed files still support shrinkage/growth; growth is bounded by the same compressed-input ceiling. Final deadline checks are retained.
- Set and restore stdout's nonblocking flag once per complete output operation, instead of once for the header and every output batch. Scoped restoration remains active for errors/cancellation/deadlines. Per-write deadline/cancellation checks and EAGAIN polling remain unchanged.
- Assert that pipe output restores the `O_NONBLOCK` state after success and timeout, including a descriptor that was already nonblocking.

Commands and evidence:

- `python3 build.py`: three CLI-only release builds; exit 0. Exact commands in `build-commands.json`. The initial diagnostic compile omitted the baseline package identity and was rejected by package access control; the corrected compile uses the baseline identity, not a changed access level.
- `python3 /private/tmp/swiftjli-round4-cli/Scripts/test-cli.py --binary /private/tmp/swiftjli-round4-cli-evidence/candidate/swiftjli-cli --output /private/tmp/swiftjli-round4-cli-evidence/cli-tests-verified`: exit 0, 252 process checks. Log and structured report retained. Two earlier test-harness failures are retained separately: comparing all Darwin pipe flags (the kernel also sets unrelated 0x10000), and a test-local variable shadowing a later installer fixture. Neither required a production change.
- `python3 phases.py`: five warmups and twenty diagnostic samples on each of five fixtures. Raw samples and commands in `phases.json`.
- `python3 run-size-hint.py`: exit 0, five checks passed; compiler command in `input-size-hint-command.json`. Diagnostic interposition changes only the synthetic input's stat/fstat hint. Hints 0, size-1, exact size and size+1 produce identical PNM output; size-1 plus that exact input ceiling rejects the extra byte with exit 5 and zero stdout. No production interposition/environment hooks exist.
- `git diff --check`: exit 0.

Diagnostic median main-to-exit time: flat19 0.246 ms, flat512 0.369 ms, noise512 2.845 ms, flat3072 5.291 ms, DCT12_512 2.540 ms. Whole-process times for this *instrumented*, direct-launch diagnostic were 5.483, 5.491, 8.159, 10.704 and 8.268 ms respectively. These are not acceptance benchmarks and use no `/usr/bin/time` wrapper. Most small-image launch time lies outside the measured main-to-exit interval; there is no safe claim that these small I/O changes eliminate the loader/runtime floor.

Output scratch stays bounded and owning. The only new pointer is a synchronous borrow of a stack byte during `read`; it never escapes. Existing decoded image/output buffer owners and write scopes are unchanged. Peak RSS differences require separate controlled timing; avoiding one allocation alone is not a whole-process memory claim.

## Paired release benchmark

Command (exit 0):

```sh
python3 Scripts/benchmark-djpeg.py \
  --baseline /private/tmp/swiftjli-round4-cli-evidence/baseline/swiftjli-cli \
  --candidate /private/tmp/swiftjli-round4-cli-evidence/candidate/swiftjli-cli \
  --djpeg /opt/homebrew/Cellar/jpeg-turbo/3.2.1/bin/djpeg \
  --matrix lossless-patterns \
  --fixtures /private/tmp/swiftjli-native-matrix-fixtures \
  --output /private/tmp/swiftjli-round4-cli-evidence/paired-cli-lossless.json
```

Five warmups, twenty samples, two balanced rounds. No concurrent build/test/profiler jobs. Complete hashes, commands, exact-output checks, latency distributions and RSS samples are retained in the JSON. `paired-cli-summary.json` gives per-case changes.

All 13 eligible cases in each round have exact baseline/candidate PNM bytes and zero sample differences against djpeg. The same three large noise/mixed cases remain resource-limit exclusions. No latency change reaches the 5% investigation threshold (range -3.11% to +4.24%); this is not a new small-image latency win. The existing five large wins against djpeg remain. All four 19×19 profiles reduce median process RSS by 96 KiB in both rounds, except mixed19 round 2 at 112 KiB. Other RSS changes range from a 104 KiB reduction to a 16 KiB increase. No general memory win over djpeg is claimed.

Recommendation: retain the smaller bounded input scratch requirement and fewer output descriptor syscalls. Do not advertise a >5% latency improvement or closure of the startup gap. Independent source review by the audit agent found no actionable issue in size/resource checks, synchronous borrows or descriptor restoration.

Full Swift Build rebuild, sanitizers and other platform gates remain root integration work; this change touches only the executable and its black-box regression script.
