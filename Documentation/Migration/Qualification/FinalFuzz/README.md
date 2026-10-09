# Final four-entry fuzz campaign

Shipping source `0a714f32a2ef5e1b8be48f6b02500e43833489d2` passes four
independent 3,600-second campaigns: inspect, inspectJPEG, allocating decode and
caller-destination decode. Every process exits 0, emits its completed event after
at least 3,600 seconds, accepts conformant input and rejects malformed input.
No unresolved crash, hang or bounds finding occurred. Source/binary/container
hashes, exact commands, raw progress logs, error categories and RSS are retained.
This finite mutation campaign is not coverage-guided fuzzing or a security certification.

Run `caffeinate -i python3 Scripts/run-decoder-fuzz.py --output-dir <fresh-dir>`
on macOS. The temporary assertion ends with the command. The preceding aa6e298
attempt was interrupted by host idle sleep at about 44 minutes; the watchdog
failed that attempt correctly. It is not counted as an hour-long pass.

The retained .gz files preserve original log bytes. The binary is identified by
hash and rebuilt by the recorded command; it is not committed as a platform binary.
