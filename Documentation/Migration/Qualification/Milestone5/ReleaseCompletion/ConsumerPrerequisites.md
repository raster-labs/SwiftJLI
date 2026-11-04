# DICOMKit successor prerequisites — 4 November 2026

**Source inventory only; actual successor integration remains unexecuted.** The
consumer baseline is `5756e6408a95649b463d4a6408f2957fe1b4c212`. Its selected
predecessor-backed [baseline tests](dicomkit-baseline/README.md) pass. This inventory
informs the pending scope decision; it does not replace that decision or qualify
new adapters. Suite policy Decision D3 specifies coordinated four-codec cutover
and Apple deployment minima of 26.0.

| Successor source inspected | Available implementation | Work required to preserve the consumer contract |
| --- | --- | --- |
| SwiftJLI prepared revision `7739dba554cabebcc25e3593af3feb6ba27f8489`, library bytes equal `f548e5048e5c71204c2a2ec4036bf66c4f040285` | Public owning asynchronous JPEG operations, explicit limits and caller destination; package-only synchronous CLI adapters. | DICOMKit's current managed JPEG route requires caller-owned workspace, nonthrowing scalar outcomes and a synchronous admitted worker. Neither the ordinary async API nor the private CLI adapter establishes those guarantees. A complete managed cutover requires a designed and qualified specialised API or an explicitly approved consumer contract change. |
| SwiftJLS local committed source `a9bf9e95933fc8135bbcc3922d6ce831ddfe2057` | Public `QualifiedMonochromeDecoder(profile: .jlswift0101)` with synchronous borrowed input/output/workspace, scalar failure/cancellation and fixed workspace. Manifest, common API and qualified API matched the commit; unrelated optimisation files in that checkout were dirty and are excluded from this inspection. | Map DICOMKit's managed JPEG-LS ownership ledger, limits, failure fields, cancellation and partial-output rejection. The profile is monochrome and does not replace ordinary multicomponent encode/decode. A separate adapter and consumer execution evidence remain necessary. This is local committed-source evidence, not a remote release/whole-checkout qualification claim. |
| SwiftJXL clean local source `3e00d934bef331cdbc7c4be752857dc9eca8f799` | Public async unsigned pixel operations and original-JPEG reconstruction. | Current DICOMKit synchronous APIs and signed16 offset-binary interpretation need explicit adaptation. Preserve distance/quality policy, padding and original-JPEG reconstruction. Qualify the selected source's profile ceilings, including reconstruction up to 2048 per axis and lossy encode up to 4096 per axis / 4,194,304 pixels. |
| SwiftJ2K remote main `46be90fc3bf50429956725ee592687d8ff8e7344` | Actual products `SwiftJ2K`, `SwiftJ2K3D`, `SwiftJ2KJPIP`; retained image, encoder/decoder/transcoder, volume, JP3D and JPIP declarations. No local checkout was found; inspection used read-only GitHub contents at this commit. | Consolidate six predecessor products into three and compare actual call shapes. Public accelerated selection does not directly express the consumer's distinct explicit CPU/GPU API modes. The inspected legacy resolution bridge downsamples after decode, while the existing consumer promises partial-resolution decoding; preserve that behaviour/cost contract through an appropriate qualified path rather than silently substituting the bridge. |

## Source paths and evidence boundaries

SwiftJLS's relevant declarations are in
`Sources/SwiftJLS/Qualified/QualifiedMonochromeDecoder.swift` and
`Sources/SwiftJLS/Qualified/QualifiedOutcome.swift`. The latter declares
`QualifiedOutcome`, `QualifiedFailure` and `QualifiedCancellation`; its maintenance record
pins predecessor `d17545284a23e93f3d884a18f1046c4e305daa35`, matching DICOMKit's lock.
The existing API is an advanced synchronous exception, not the common owning
shared-storage surface. Adapter validation must retain those distinctions.

SwiftJXL's unsigned guards are in `Sources/SwiftJXL/CodecAPI.swift` and reconstruction
limits in `Sources/SwiftJXL/Transcoding.swift`. DICOMKit's existing signed handling
is in `Sources/DICOMCore/JXLCodec.swift`. Reversible signed interpretation must be
proved; changing the descriptor to unsigned alone is insufficient.

SwiftJ2K's [manifest](https://github.com/raster-labs/SwiftJ2K/blob/46be90fc3bf50429956725ee592687d8ff8e7344/Package.swift)
and [legacy resolution bridge](https://github.com/raster-labs/SwiftJ2K/blob/46be90fc3bf50429956725ee592687d8ff8e7344/Sources/SwiftJ2K/LegacyImageBridge.swift#L1498)
were read at the exact source above. DICOMKit uses `J2KSwiftCodec.decodeFrameAtResolution`
and explicit GPU routes. Absence of a local successor checkout is not evidence
that its runtime products are missing. Existing Part-2 refusal and unavailable
consumer JPIP behaviour must not become advertised functionality through renaming.

The pinned JPEG predecessor `b6df774a3c3ecdf4b98971f31543fdd18074ace2` contains
`JLILosslessCallerStorage.swift`, `JLIBaselineCallerStorage.swift`, their parse storage,
`JLICoreStorage.swift` and `JLICoreFailure.swift` (900 lines collectively), plus
changes in the canonical marker, entropy, predictor and reconstruction code.
Copying only the six helper files would not migrate their dependencies or prove
allocation-free scalar execution. Relevant maintenance invariants include scan-local
DRI/table state, disjoint borrowed spans, full arena retention and bounded cancellation.
No source migration has been performed by this inventory.

An explicitly staged SwiftJLI integration could expose an opt-in asynchronous
adapter while retaining the current managed and synchronous routes. That would
be an implemented integration route, not the coordinated managed cutover specified
by D3, and must be labelled and qualified accordingly if the owner selects it.
No scope exception, unsafe pointer bridge, semaphore adapter, precision reduction
or managed-memory fallback is inferred from this report.
