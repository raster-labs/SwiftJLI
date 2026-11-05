# Final fuzz and source-freeze audit

**Passed** at checkout `07cc31e2f3eeb8e22cb12d1fe519e605ef5cffed`, with shipping
source `f548e5048e5c71204c2a2ec4036bf66c4f040285`. This is a read-only evidence
audit; no build, test, fuzz or benchmark was rerun.

[fuzz-source-freeze.json](fuzz-source-freeze.json) records the verified facts:

- All four compressed campaign logs and the build log reproduce their recorded
  raw byte lengths and SHA-256 values; compressed hashes also match.
- Each campaign has one start, 3,599 progress records and one completion,
  at least 3,600 elapsed seconds, a successful exit and both accepted/rejected
  cases. Counters remain monotonic; attempts equal accepted plus rejected at
  every checkpoint. Final error-category totals equal rejected counts.
- No failure event, internal-failure category or failure-seed file is present.
  The supervisor's retained exit is zero. This finite observation is not a
  security certification or proof about every input.
- All 49 package/shipping/fuzzer files match both the pinned Git revision and
  current bytes; the supervisor matches its recorded and pinned hashes.
  The 3,481,008-byte executable retained outside Git is available and matches
  SHA-256 `345f5ae488f3ee0d2d7022580204bbba2e8af41a397d0dc4a4c7bd0468cc12fc`.
- The retained Docker inspection identifies the same image ID and registry
  RepoDigest, Linux ARM64. Each worker command uses that immutable image,
  one CPU, 256 MiB and the private executable with a read-only source mount.

The [live PR metadata snapshot](pr-source-freeze.json) confirms PR #26 still
targets `codex/milestone-5-baseline-8ae2762` at exact commit
`8ae2762710d6279cd92222f5bb5ca95f042f694e`. Git ancestry includes that baseline
and f548, and excludes `bbb0b1a9a602807643fc254fb4e0d54a162d5ae8`. Only
`NativeExecution.swift` differs in shipping source from the baseline. The
explicit owner confirmation names the same base, shipping pin and excluded
performance head; the earlier assumption and later confirmation remain separate.
This verifies the current ref value, not an immutable-branch permission rule.

All **98** local links checked in the current summary sections resolve. Current
documents qualify only the matched baseline-to-f548 callback-owner comparison,
state its desktop-load and tail-latency limitations, and exclude the concurrent
performance implementation. No claim qualifying that newer implementation was
found. The initial PR snapshot called completed fuzz/performance work pending;
that finding is retained in the original receipts.

**Follow-up, 2026-11-03 at 09:44 UTC:** the [fresh PR receipt](pr-source-freeze-follow-up.json)
confirms that the description now records the full-hour fuzz campaigns and
scoped performance screen as passed. The stale sentence is absent. The PR base
remains exact `8ae2762` and its head remains `07cc31e`; all 49 source files still
match the original audit hashes, Git HEAD and the frozen shipping revision.
The original PR snapshot and audit receipt are unchanged. This resolves the
PR-body finding only; the scoped Apple CI retry remains unqualified here.

The latest retained security check still reports private reporting disabled and
the CLI account without administrator access. Final 07cc hosted CI acceptance,
physical-device qualification and security-channel activation are outside this
audit; no pass is inferred for them.
