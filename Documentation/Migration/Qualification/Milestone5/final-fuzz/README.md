# Final-candidate full-hour fuzz qualification

**Passed:** all four public decode-entry campaigns completed at least 3,600
seconds and exited zero. The supervisor also exited zero. Shipping source is
`f548e5048e5c71204c2a2ec4036bf66c4f040285`; all recorded source, supervisor and
private executable hashes still matched at completion. Later documentation and
qualification-tool changes do not replace the source pin.

| Entry | Attempts | Accepted | Rejected | Elapsed seconds | Peak process RSS bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| inspect | 613,452,420 | 226,601,867 | 386,850,553 | 3600.000041549 | 24248320 |
| inspectJPEG | 605,043,714 | 223,495,207 | 381,548,507 | 3600.000055446 | 24154112 |
| allocate | 63,780,834 | 16,393,624 | 47,387,210 | 3600.000024477 | 25899008 |
| destination | 59,345,839 | 15,239,049 | 44,106,790 | 3600.000053916 | 25792512 |

[campaign.json](campaign.json) retains the exact compiler, source hashes,
private-binary hash, container commands, limits, error categories and completion
records. [archive.json](archive.json) records terminal hash verification,
registry image digests and the lossless log archive. Every entry exercised both
acceptance and defined rejection. No crash, watchdog expiry, internal-failure
finding or unresolved bounds finding was reported by this finite experiment.

The exact supervisor invocation was:

```sh
python3 Scripts/run-decoder-fuzz.py --seconds 3600 \
  --output-dir Documentation/Migration/Qualification/Milestone5/final-fuzz
```

Reproduction must choose a new output directory. The pinned image used Swift version 6.4.2 (swift-6.4.2-RELEASE); Target: aarch64-unknown-linux-gnu. Each worker used one CPU and a 256 MiB container memory
limit, a private executable copy and a read-only source mount. The campaigns
ran concurrently as deterministic scalar mutation fuzzing in ordinary Release,
without sanitizers. The required duration is per entry, not four shorter runs
added together. Separate ASan/TSan and oracle records retain their own scope.

The original logical `.jsonl` logs and `build.log` are retained as `.gz` files;
archive hashes verify the original bytes after decompression. The generated
executable is retained outside Git at the local path in `archive.json`; its
original hash remains in both receipts. No failure seed was emitted. The
interrupted pre-fix campaign remains separately labelled partial evidence.

This is not coverage-guided fuzzing, a security certification, a physical-device
memory limit or proof about every hostile input. RSS is whole-process high-water
memory. Concurrent desktop work during fuzzing does not supply performance
benchmark evidence; the matched timing experiment was run afterwards.
