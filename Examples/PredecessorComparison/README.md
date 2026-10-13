# Same-platform predecessor comparison

This development-only package runs two pinned JLISwift references and the local
SwiftJLI checkout on the same Apple runtime. Run both modes to cover all 71
records; neither mode alone proves complete decoded identity.

- Default: `0a4ded0b0b2e8e38127f4f302b286e74ee352474`, the unchanged migration
  baseline, checks all 71 encoded records and the 64 unaffected decoded records.
- `JLISWIFT_CENTERED_REFERENCE=1`: `981da4efb7d62e4370c5d6de706d56a729b9552e`
  (v0.5.2) checks all 71 encoded records and the seven corrected decoded records.

The exact seven-case selection is in `IdentityExpectations.swift`. No decoded
case is omitted across the two runs. This keeps the original 4:4:4 interpretation
and verifies the centred-chroma correction against live same-platform output,
without replacing an iOS oracle with frozen macOS floating-point hashes. Neither
codec is changed and no shipping dependency is added.

The three support sources in each target come from
`Tests/SwiftJLITests/Support`. Only the import and visibility of
`identityHashRecords` differ. Preserve their Apache-2.0 notices.
The frozen main-suite reference was generated on macOS ARM64; it is not an
independent iOS floating-point oracle. Integer predictive hashes remain checked
on every platform. This package supplies the live platform-specific comparison.

Run on macOS with `swift run -Xswiftc -enable-testing CompareIdentity` in each
mode (set the environment variable for the second run), or from
the repository root on an installed iOS 26+ simulator:

```sh
python3 Scripts/test-apple-simulator.py --package-path Examples/PredecessorComparison --scheme PredecessorComparison --output /tmp/swiftjli-live-predecessor
JLISWIFT_CENTERED_REFERENCE=1 python3 Scripts/test-apple-simulator.py --package-path Examples/PredecessorComparison --scheme PredecessorComparison --output /tmp/swiftjli-centred-predecessor
```

The actual predecessor imports CryptoKit unconditionally, so the package does
not build on the standard Linux Swift image. The predecessor is left unchanged;
the main library and its integer/reference tests remain qualified on Linux.
