# Same-platform predecessor comparison

This development-only package runs the pinned JLISwift revision
`0a4ded0b0b2e8e38127f4f302b286e74ee352474` and the local SwiftJLI checkout
on the same Apple runtime. It requires all 71 encoded-byte and decoded-sample
records to match exactly. It does not change either codec or add a shipping dependency.

The three support sources in each target come from
`Tests/SwiftJLITests/Support`. Only the import and visibility of
`identityHashRecords` differ. Preserve their Apache-2.0 notices.
The frozen main-suite reference was generated on macOS ARM64; it is not an
independent iOS floating-point oracle. Integer predictive hashes remain checked
on every platform. This package supplies the live platform-specific comparison.

Run on macOS with `swift run -Xswiftc -enable-testing CompareIdentity`, or from
the repository root on an installed iOS 26+ simulator:

```sh
python3 Scripts/test-apple-simulator.py --package-path Examples/PredecessorComparison --scheme PredecessorComparison-Package --output /tmp/swiftjli-live-predecessor
```

The actual predecessor imports CryptoKit unconditionally, so the package does
not build on the standard Linux Swift image. The predecessor is left unchanged;
the main library and its integer/reference tests remain qualified on Linux.
