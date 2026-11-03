# Standalone certified mirror prototype — source only

This is an unbuilt, unexecuted experiment outside the repository. It does not change any codec, public API, memory reservation or Float32 route. The parent must grant a CPU slot before any command below is run. The frozen `ba2771e` FMA composition is a numerical reference, **not an accepted production candidate**.

`CertifiedMirror.swift` keeps the first pass and dequantisation graph exactly as `BlockLocalIDCT` at ba2771e, reading the actual frozen module's matrix and permutation values. It uses independent owning input, first-pass and integer-output arrays. There are no candidate raw pointers or in-place binding changes. The frozen-reference adapter temporarily rebinds its own consumed coefficient array inside the array borrow and copies the Float results before returning.

Pass two uses an original even/odd mirror butterfly. Its eight Double weights include the actual Float-basis mirror residual and the reference/candidate FMA rounding depths. The proof is in the adjacent design report at `/private/tmp/swiftjli-round5-evidence/factorised-idct-design/README.md`.

## Executable enclosure details

- `fegetround()==FE_TONEAREST` is required before constant construction and each transform. No code changes the rounding mode.
- Actual original and mirrored basis values must be finite, have magnitude in `[1/16,1/2]`, and be integral multiples of `2^-27`. Otherwise every row falls back.
- Accepted row inputs must be finite, at most `2^32` in magnitude and integral multiples of `2^-27`. Their exact second-pass products/partial sums therefore lie on the `2^-54` grid and remain below `2^34`; nonzero intermediates cannot be subnormal or overflow. Internal nonfinite, excessive or finer-grid rows use the exact SIMD reference, preserving its clipping/error outcome.
- Each `gamma` constant, weight product and weight sum is rounded upwards with `nextUp`. Residual subtraction is exact in Double in the checked basis range. Midpoint construction uses a Double sum/division followed by the intended Float rounding; its residual is still measured against the actual stored basis.
- Runtime row radii use eight explicit positive Double FMAs. Their inputs are zero or far above Double underflow in the accepted domain. An upper-enclosed `1/(1-gamma8_double)` inflation and a final `nextUp` cover possible downward accumulation rounding.
- The certificate computes outward Double endpoints for the uncentred reference value. It converts each endpoint to Float, then applies the original Float centre addition, clipping and nearest-away rounding. Monotonic RNE fixes every possible reference Float, so identical endpoint integers certify the entire interval. No `x+0.5` approximation is used.
- Invalid/nonfinite sample or radius returns no certificate. The fallback executes the original eight ascending Float FMAs for that pixel. Every integer conversion is preceded by a finite/range check or uses finite clipped endpoints; NaN is never converted to UInt16.

The test corpus is source-ready, not evidence of passing results. It includes every isolated frequency and sign, positive/negative coefficient extrema, quantisers1/65535/alternating/ramp, dense deterministic inputs, larger internal Int32 extrema, zero/interior/clipped rows, and five neighbours around every8/12-bit half threshold. Invalid radii and nonfinite/subnormal/out-of-domain rows exercise explicit fallback. Row-level boundary cases are labelled separately from encoded JPEG coefficient cases.

Read-only extraction of the recorded synthetic JPEG fixtures is prepared for execution. It uses the frozen module's parser and original Swift entropy decoder, copying each bounded coefficient borrow synchronously. It cannot be performed without running the probe, so no coefficient or fallback result exists yet. Extraction includes dense8/12-bit512 images, DCT12, flat/tiny cases and late-AC cases. Raised input/workspace limits are diagnostic only.

All64 samples of each coefficient block are compared and counted, including padded edge positions. Tiny/odd-size fallback counts are therefore block-transform counts, not cropped-image pixel rates.

Correctness mode compares every coefficient-case integer against the frozen `BlockLocalIDCT` result, verifies the copied exact graph's Float bits against that same result, and independently evaluates each candidate interval against the exact second-pass dot product. Row-level boundary cases additionally check scalar fallback FMA bits against the SIMD reference. These are numerical/prototype checks, not product lifecycle or platform qualification.

## Prepared execution

The runner pins the compiler, all prototype sources, object/module/modulemap/header identities and fixture hashes. It refuses to overwrite receipts and checks identity again after each action. A new run name retains failed attempts separately. `source-receipt.json` records a snapshot without running the compiler or codec.

```
python3 run.py build --run-name initial --cpu-grant
python3 run.py correctness --run-name initial --cpu-grant
python3 run.py timing --run-name initial --cpu-grant
```

Timing requires successful correctness with the exact same binary. The two source-level timing arms share the same owning buffers, exact first pass and output allocation. Runs alternate exact/certified order, with five warmups and20 measured samples. Full output comparison and hashing are outside the timer. Certificate bookkeeping is included. This measures a standalone transform prototype; it is not a comparison of the frozen in-place API's allocation boundary, a full decode, djpeg/libjpeg, RSS or production latency. Shared-host results must remain provisional.

No implementation should be integrated based on this source preparation alone. FMA reference qualification, exact integer tests, untouched Float32 behaviour, product lifetime/cancellation/race coverage and unchanged-options performance controls remain prerequisites.
