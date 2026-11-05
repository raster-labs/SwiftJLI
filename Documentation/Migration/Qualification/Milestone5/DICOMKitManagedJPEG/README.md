# Qualified JPEG integration handback

The specialised API implementation and its focused checks pass at the shipping-source hashes in [receipt.json](receipt.json). Base worktree commit is `ec9843013adc7b0b6064312a1333354e601509b1`; the source manifest also includes the separately owned predictive colour API edits. This is an uncommitted integration candidate, not a release or completed DICOMKit cutover.

- Final Release, AddressSanitizer and ThreadSanitizer each pass **13 test declarations / one suite**. Parameterised cases include 13 independent baseline fixtures and all seven lossless predictors; those cases are not counted as separate test declarations.
- **41 exact predecessor/candidate pixel comparisons** pass: 13 baseline fixtures under automatic, RGB and YCbCr interpretation, plus independent 8/12-bit lossless fixtures. The predecessor is `b6df774a3c3ecdf4b98971f31543fdd18074ace2`. Its Debug objects and candidate Release objects were compared for bytes only, not speed.
- **18 cold processes** pass: C and Swift allocation controls each observe one allocation; 16 success/cancellation/malformed/empty-entropy/missing-DQT operations observe zero instrumented allocation and mapping calls. A separate mmap positive control observes one mapping. Counts exclude caller setup, worker/bootstrap/stack and arbitrary callback work, and were obtained outside sanitizers.
- Missing referenced DQT now fails with scalar code178 before pixel writes; the test checks untouched arena bytes and normal recovery. Dimension/workspace limits are enforced in the core plans before writes, preserving code173. Each operation parses once.
- The final reproduction runner rejects an existing output directory with exit2 without changing any of its 45 files or creating scratch storage.

[QualifiedJPEG.md](../../../QualifiedJPEG.md) defines the public API, exact profile, source extraction, memory model and stricter malformed-input boundaries. The [earlier record](../DICOMKitManagedJPEG-before-missing-dqt/receipt.json) preserves the initial ownership probe, pinned predecessor 17-test baseline, failed development/probe attempts and earlier source-bound results. Earlier results are not substituted for the final source.

Reproduce the public-product allocation matrix from the repository root:

```sh
python3 Examples/QualifiedJPEGProbe/run.py --output /private/tmp/qualified-jpeg-new-evidence --scratch /private/tmp/qualified-jpeg-new-build
```

Both directories must be fresh. The [probe README](../../../../../Examples/QualifiedJPEGProbe/README.md) gives instrumentation scope and the independent mmap calibration. Final sanitizer and parity commands/exits are in [final-checks-command-receipt.json](final-checks-command-receipt.json); the Release command is in [receipt.json](receipt.json). Compressed logs retain unfiltered output. No generated executables or sample-output dumps are retained in this evidence directory.

Full library/CLI and actual DICOMKit managed-budget/worker tests, supported remote toolchains/platforms, new-entry fuzz campaigns and controlled performance requalification remain separate gates. Physical-device qualification is unexecuted. No universal zero-allocation, speed, security, clinical or conformance claim follows from this focused handback.
