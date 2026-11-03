# Remaining memory targets — source inspection only

Pinned source: `6e763ec2099e162bae52a40109ff74269ea9899f`. No allocation profile or VM-region inspection has executed for this note. Quantities below are explicit payload sizes, not measured RSS or proof of its cause. An independent source review reached the same conclusions.

The unchanged comparator requires retained compressed Data and one complete decoded output at equal precision/extent. A2048² twelve-bit image uses an8MiB output on each side; DCT values may differ by1 within the fixed gate. Swift `OwnedImageStorage.finishAndSeal` moves the existing array reference into immutable storage without cloning pixel contents. The C helper owns one complete calloc output. Eliminating required pixels, retaining fewer output samples or changing precision is not a valid optimisation.

The admitted Apple ARM64 greyscale FMA path has no full-frame coefficient, natural-order, Float reconstruction or component plane. Its explicit payload is:

| Path | Coefficient/output payload | Separate Float window |
|---|---:|---:|
| Pipeline | 2×256×64×4 =128KiB |0 |
| Serial | at most256×64×4 =64KiB |0 |
| Table-proven DC only | at most1024×(4+4) =8KiB |included |

A qualifying scan also has one8192-entry UInt32 AC lookup (32KiB), a256-byte Float quantiser and two fixed C Huffman metadata values of1048bytes each. The pipeline additionally owns two semaphores, a DispatchGroup, mutex/error state and one joined worker. Source cannot determine committed worker-stack pages, allocator size classes/caches, type-metadata faults or executable-code residency. Both comparator modes load the same executable and linked libraries, so the residual gap must not simply be labelled “Swift runtime overhead”.

`JPEGBytes` retains one immutable NSData snapshot; scan ranges share that owner. It does not copy every entropy segment. A bridge can copy for some Data representations; the parser's allowance for a possible copy is not evidence that these fixtures actually copied. `JPEGParserReservation.fixedReserve` is a1MiB admission allowance, **not an allocated1MiB scratch buffer**. Lowering the reservation cannot itself reduce RSS. Table/dictionary snapshots preserve scan-local redefinitions through value semantics and COW.

The smallest credible remaining source target is `JLIDecoder.swift:131–132`: the streaming path calls `prepareDCTables` and `prepareACTables` to fill default table IDs0/1, then selects only one ID. A supplied greyscale ID0 can therefore trigger dictionary COW and lazy construction/retention of unused chrominance defaults, including unused encoder maps. Resolving just the selected ID with the exact existing fallback semantics would avoid that work: preserve a present ID, use chrominance for missing ID1, and luminance for missing ID0 or any other missing ID. This is a small allocation/cold-start hypothesis, not a demonstrated RSS or latency gain.

A broader table-payload coalescing design could reduce multiple small Huffman allocations, but must preserve scan-local replacement snapshots. Shrinking the128KiB slots or32KiB lookup is a throughput/overlap trade-off, not free memory; prior narrow-slot and lookup trials were not accepted. Removing the joined worker would sacrifice the measured overlap and requires its own latency gate. No such code change is authorised by this note.

A separate retained-output diagnostic should measure malloc regions, stack residency and executable pages before selecting a further target. It must leave the official comparator and results intact and report access/measurement limitations directly.
