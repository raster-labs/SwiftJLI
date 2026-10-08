# Apple runtime evidence

At shipping source `0a714f32a2ef5e1b8be48f6b02500e43833489d2`, CI run
37769853487 passed the macOS debug/release and separate ASan/TSan job, native
macOS Intel debug/release and 107 CLI/install/manual checks, and all four Linux
toolchain/architecture jobs. Nine SDK targets also compile.

The iOS library suite passed 347 tests on iOS 26.5 Simulator (iPhone Air).
Its separate live predecessor comparison did not execute: Xcode generated
`PredecessorComparison`, whereas the first command requested
`PredecessorComparison-Package`. That setup failure is retained and corrected
in the next workflow. The overall run remains failed; successful component
checks must not be presented as an entirely green run.

The following run at 7d85c34 adds tvOS, visionOS and watchOS simulator execution.
All 13 jobs pass. iOS, tvOS, visionOS and watchOS each pass 347 library tests;
the additional live iOS predecessor test compares all 71 records exactly and passes. Simulators
cannot establish physical Watch device memory ceilings.
