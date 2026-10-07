# One-hour checkpoint campaigns

`campaign.json` records the exact source revision, source/binary hashes, compiler, immutable Docker image and three completed entry results. Each `.jsonl.gz` contains the original progress/completion log. `archives.json` records both the archive hash and the uncompressed hash (the latter also appears in the campaign manifest).

Reproduction uses a checkout at `1072de44ee31e626886efb5cb9e37215648c3db8` and that revision's `Scripts/run-decoder-fuzz.py`, with its default one-hour duration. The later supervisor has a fourth JPEG-specific inspection entry and a private executable copy per campaign; it is not the historical runner represented here. The executable itself is not committed; rebuild from the pinned sources and recorded toolchain/image.

These campaigns passed at the pinned checkpoint. They do not qualify later code, every input, every platform or coverage-guided fuzzing. Inspection success is structural acceptance and is not proof that entropy reconstructs valid samples.
