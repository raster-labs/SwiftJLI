# Large DCT oracle, prepared source only

Target source `5f9e1cf50db4eee4d5439f80602f3dfe9f24b0cd`. The frozen products are from the independently qualified full Release build, not a fresh candidate build. Source templates came from the unexecuted281f preparation; this copy adds strict command/restart checks, decoded descriptor checks and untouched padded destination bytes.

Eight profiles:513x257 greyscale,8/12-bit precision, sequential quality85, no adaptive quantisation, restart intervals3 and1023 MCUs, scalarCPU and automatic policies. Each direction compares Swift and djpeg on the same compressed stream: Swift encoding→djpeg is checked against Swift self-decode; cjpeg encoding→Swift is checked against djpeg decode. Fixed maximum differences are2 sample units at8-bit and4 at12-bit. These tolerances cannot be changed by command-line arguments. This is16 decoder comparisons, not a lossy-output-versus-original comparison. Odd image edges and2,145 blocks exercise partial rows and multiple canonical batches; restart1023 straddles a1,024-block batch boundary.

No compiler or codec was run during preparation. Python sources were parsed as syntax only. To execute after CPU grant:

```sh
python3 /private/tmp/swiftjli-round5-evidence/c-final-5f9e1cf/large-dct-oracle/build.py --execute
python3 /private/tmp/swiftjli-round5-evidence/c-final-5f9e1cf/large-dct-oracle/run.py --execute
```

Both scripts otherwise print an unexecuted plan. They refuse existing attempt directories; select a fresh `--output` for any retry and pass its successful build directory via `--build-dir`. Every command has status/exit/log receipts, including timeout/launch errors. The build verifies pinned objects, imported Swift modules, modulemap and its actual umbrella header, then rechecks them after compilation. Runtime pins the built binary, both libjpeg-turbo3.2.1 executables and harness sources, records versions, full sample comparisons and output hashes, and rechecks identities at completion. Executables and generated JPEG/PNM payloads should be omitted from the archive; retain hashes and text receipts.

Default public resource limits remain in effect. This runner has no timing/RSS claim and no new shipping dependency. Separate large-lossless CLI coverage is documented in its audited sidecar; it does not cover scalar-policy selection.
