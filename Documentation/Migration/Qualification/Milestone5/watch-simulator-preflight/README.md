# Local Watch simulator preflight — unavailable

No Watch harness tests executed locally: **zero tests, zero
`WATCH_QUALIFICATION` records and no xcresult**. The requested configuration was
ordinary Release. Shipping source and the unchanged Watch harness match f548;
the checkout head is `a44e671690251ffaa15144027688f9f48593752a`.

Xcode **27.2 (27B52)**, Swift **6.4.2** and watchOS Simulator SDK **27.2
(24S118)** are installed. The installed CoreSimulator framework is **1174.9.2**;
Xcode requires **1174.21.0** and disables simulator support. The package scheme
`WatchQualification-Package` is discoverable, but its Xcode destinations contain
only a generic Watch simulator placeholder, with no runnable device identifier.
The installed CoreSimulator executable independently lists five watchOS 26 and
five watchOS 27 devices. Their presence does not resolve Xcode's framework
incompatibility. See [exact bounded commands and source hashes](report.json),
[destination output](destinations.stdout) and [Xcode's diagnostic](destinations.stderr).

The initial `xcrun simctl list devices available --json` entered Xcode's shell
wrapper. Inspection showed that the wrapper automatically invokes
`xcodebuild -runFirstLaunch` when the installed framework is too old. Its owned
process group was stopped, returning **143**; no separate installation or update
command was issued. The framework still reported 1174.9.2 after
stopping. Subsequent enumeration invoked the installed CoreSimulator executable
directly, and all seven retained discovery commands exited zero. Their command
success is discovery evidence, not runtime qualification. No further local
framework/service changes or SDK downloads were pursued.

The qualification-only follow-up adds an explicit `--configuration` option to
the simulator runner (default Debug) and a Watch-only CI step for the existing
six-test package in Release. JSON, logs and xcresult are retained in the existing
artifact upload. [Static review](qualification-change-review.json) passes Python
AST, argument/help handling and whitespace checks. Hosted execution is pending.
The existing library simulator tests remain in place.

This record establishes neither simulator execution nor physical-device
qualification. Any later simulator RSS remains process-wide simulator/runtime
data and cannot establish a Watch device memory ceiling.
