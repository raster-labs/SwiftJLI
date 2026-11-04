# DICOMKit predecessor baseline — 4 November 2026

At source `5756e6408a95649b463d4a6408f2957fe1b4c212`, the selected native macOS Debug baseline passes **54 test declarations in eight suites**, exit **0**, using Apple Swift 6.4.2 and the explicit Swift Build engine. This is the unchanged predecessor-backed consumer. No SwiftJLI adapter is linked by this run, and the broader DICOMKit suite, sanitizers, performance and physical platforms are not qualified here.

[Exact command and exit](result.json), [source and outcome summary](summary.json), [dependency lock](Package.resolved) and the [complete compressed log](test.log.gz) retain the baseline. The worktree and dependency lock stayed unchanged. Existing compiler warnings remain in the log. Parameterised case executions do not increase the stated declaration count.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  test --build-system swiftbuild --disable-sandbox --jobs 2 \
  --filter 'JLICodecRegistryTests|StrictCompressedFrameTests|IndependentCompressedFrameTests|M7JPEGExtendedProcessTests|ManagedCodecTests|DICOMAllocationBudgetTests|DICOMExternalAllocationTests|EncapsulatedPixelDataOffsetTableTests'
```

The relevant manifest, lock, JPEG adapter, image-codec API and allocation contract still match the earlier `ff9d26f` audit byte-for-byte. Integration must preserve this managed ownership/execution contract; this baseline is not acceptance of a new adapter or dependency cutover.
