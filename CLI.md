# swiftjli-cli: JPEG and lossless JPEG command-line tool

Version **1.1.0-dev.2**; Swift 6.2 minimum with Swift 6.4 qualified / Swift 6, Apple OS minimum **26.0**. The CLI targets macOS and Linux; see the [acceptance ledger](Documentation/Migration/ACCEPTANCE.md) for evidence revisions. No external parser package or sibling codec is required.

`swiftjli-cli` provides `capabilities`, `encode`, `decode`, `inspect`, `validate`, `help` and `version`:

```sh
swift run swiftjli-cli --help
swift run swiftjli-cli capabilities --json
swift run swiftjli-cli inspect -i image.jpg --json
swift run swiftjli-cli validate -i image.jpg
swift run swiftjli-cli decode -i image.jpg -o image.nrrd
swift run swiftjli-cli encode -i image.nrrd -o roundtrip.jpg --mode lossless
swift run swiftjli-cli decode -i image.jpg -o - --output-format pgm \
  | swift run swiftjli-cli encode -i - --input-format pgm -o - --output-format jpeg \
  | swift run swiftjli-cli validate -i - --input-format jpeg
```

Both global and command-local help include availability, examples, option ranges/defaults, streams, errors and manual discovery. No arguments also show help. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` with the qualified Xcode on macOS.

## Commands and Fidelity-Preserving Uncompressed Formats

- **`capabilities [--json]`**: Reports the library's actual `canEncode`, `canDecode`, `canInspect` and `formats` values without reading files.
- **`inspect -i <path|-> [--json]`**: Parses and validates the JPEG container and frame/scan headers via `Decoder.inspectJPEG` without decoding entropy scans. `isLossless` is `true` only when `codingProcess == "predictive"` (SOF3) **and** `(pointTransform ?? 0) == 0`; a non-zero point transform reports `isLossless: false`, `fidelity: "boundedError"` and `maximumAbsoluteError: (1 << pointTransform) - 1`.
- **`validate -i <path|-> [--json]`**: Validates the complete JPEG stream and entropy-coded scans via `Decoder.inspectJPEG` and `Decoder.decode` without writing decoded image output.
- **`decode -i <path|-> -o <path|->`**: Decodes a JPEG stream into a fidelity-preserving uncompressed container (`nrrd`, `pgm`, `ppm`, or `pnm`). Fails with exit status `4` before creating or modifying output if the target container cannot preserve the decoded precision, component layout, or embedded ICC/Exif metadata.
- **`encode -i <path|-> -o <path|->`**: Encodes an uncompressed `nrrd`, `pgm`, `ppm`, or `pnm` stream into a JPEG codestream. Default mode is `lossless` (SOF3); `--mode near-lossless --max-error N` selects lossless point-transform encoding (`2^Pt - 1`), and `--mode lossy` selects DCT encoding (`--quality`, `--subsampling`, `--progressive`).
- **Format Resolution and Streaming**: When reading from `-`, writing to `-`, or using a path without a recognised extension (`.jpg`, `.jpeg`, `.nrrd`, `.pgm`, `.ppm`, `.pnm`), `--input-format` or `--output-format` is required (exit `2`). Headerless raw files (`.raw`, `--input-format raw`, `--output-format raw`) are rejected with exit `4`. Named non-regular input files (such as named FIFOs, sockets, or directories) are rejected immediately without blocking with exit `6`.
- **NRRD Profile (`CLI-04`, [NRRD format specification](https://teem.sourceforge.net/nrrd/format.html))**: Attached raw NRRD (`NRRD0001`..`NRRD0005` on input, `NRRD0004` on output) for 2D single-component full-precision unsigned 16-bit greyscale (`dimension: 2`, `sizes: <width> <height>`, `type: uint16`/`ushort`/`unsigned short`/`uint16_t`, `encoding: raw`, `endian: little`|`big`, and optional `kinds: domain domain` or `space space`). Samples are interchanged as exact unscaled unsigned 16-bit integers (`0...65535`). Headers are bounded to 64 KiB and 128 lines. All `key:=value` metadata lines, detached headers (`datafile`/`data file`), skip directives (`lineskip`/`byteskip`), non-spatial `kinds`, coordinate spaces, measurement frames and any unknown `field: value` lines are strictly rejected with static diagnostics (exit `4`) so semantic metadata is never silently dropped and untrusted header text is never echoed to `stderr`.
- **Netpbm Profile (`pgm`, `ppm`, `pnm`, [PGM](https://netpbm.sourceforge.net/doc/pgm.html) / [PPM](https://netpbm.sourceforge.net/doc/ppm.html) specifications)**: Binary `P5` (1-component greyscale) and `P6` (3-component RGB) with explicit `maxval = (1 << meaningfulBits) - 1` (`3`, `7`, `15`, `31`, `63`, `127`, `255`, `511`, `1023`, `2047`, `4095`, `8191`, `16383`, `32767`, `65535`) for `2...16` meaningful bits (1 byte per sample for `2...8` bits, big-endian 2 bytes per sample for `9...16` bits). Samples are treated as direct integer sample values in `0...maxval` with no implicit ITU-R BT.709 transfer-function or gamma conversion and no sample scaling; non-power-of-two-minus-one `maxval` values are rejected with exit `4`, and any sample value exceeding `maxval` is rejected with exit `3`. Dimension products are checked against `ResourceLimits` with overflow-checked arithmetic before any descriptor or buffer allocation.
- **Codec Hand-off Counters vs Shell Serialisation**: `copyEventCount`, `pixelAllocationCount`, `peakPixelBytes` and `peakWorkspaceBytes` in `validate`, `decode` and `encode` reports reflect the library codec's `OperationReport` (where `copyEventCount == 0` proves no internal hand-off copy occurred inside the codec, and unavailable telemetry fields remain JSON `null` or `"unknown"` in text rather than `0`). They are distinct from the CLI executable's own file/stream parsing and container serialisation buffers (`readNRRD`/`writeNRRD`/`readNetpbm`/`writeNetpbm`). The CLI bounds its simultaneously retained buffers against `--max-memory`, releases the raw input buffer before invoking `encoder.encode` or after `decoder.decode`, and preflights serialised output capacity before formatting.
- **Atomic File Output, Nonblocking Stream I/O and Deadlines**: Existing destination files are refused with exit `6` unless `--overwrite` is supplied; symlinks and directories are always refused. Regular file output is staged in a sibling temporary file in the destination directory and atomically linked/renamed only after rechecking cancellation and the command-wide monotonic deadline (`--timeout`), so failed, timed-out (exit `5`) or signal-cancelled (exit `130`) runs never leave partial destination files. Stream I/O (`-i -` / `-o -`) sets `O_NONBLOCK` on the descriptor, retries `EAGAIN`/`EWOULDBLOCK` via bounded `poll` slices against the command deadline, and restores the inherited blocking flags before exit; when streaming binary output to `stdout` (`-o -`), bytes already written to the pipe before a downstream reader closes or a timeout/signal fires cannot be retracted from the stream, and the process terminates with the corresponding non-zero exit status (`5`, `6`, or `130`).

## Verbosity

| Level | Cumulative stderr diagnostics |
| --- | --- |
| 0 (default) | Errors only |
| 1 | Version/operation summary |
| 2 | Command stages |
| 3 | Capability/descriptor details |
| 4 | Elapsed timing |
| 5 | Bounded execution trace |

`-v` increments, `-vv` through `-vvvvv` group increments, and `--verbose LEVEL`, `--verbose=LEVEL`, `-verbose: LEVEL` or `-verbose:LEVEL` set an explicit level. Digits 1..5 and `+`..`+++++` are equivalent. Bare `--verbose` / `-verbose` increment once. Options apply in order; exceeding 5 or supplying an invalid level returns 2. `--quiet` / `-q` conflicts with any positive verbosity. Errors still print in quiet mode. Help, version, capability, inspect and validate reports (and `-o -` binary payloads) use stdout; `--json` reports for `encode` and `decode` use stderr so binary stdout is never contaminated. Diagnostics never log payload bytes, metadata, raw addresses or input/output paths.

## Install or update the binary and UNIX manual

Run the installer from this source checkout. It builds the release executable and installs both the binary and matching manual every time; rerunning updates both. No administrator command runs automatically.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/install-cli.sh --prefix "$HOME/.local"
"$HOME/.local/bin/swiftjli-cli" --help
man -M "$HOME/.local/share/man" swiftjli-cli
```

Default prefix is `/usr/local`; choose an absolute writable prefix. Add its `bin` directory to PATH. For ordinary `man swiftjli-cli` lookup with a custom prefix, configure MANPATH to include `PREFIX/share/man` while retaining system defaults (for example `export MANPATH="$HOME/.local/share/man:${MANPATH:-}"`). Direct `man -M` needs no index refresh. The page is [ManPages/swiftjli-cli.1](ManPages/swiftjli-cli.1). A packaging recipe must install both `PREFIX/bin/swiftjli-cli` (0755) and `PREFIX/share/man/man1/swiftjli-cli.1` (0644).

`--destdir /absolute/staging` (or DESTDIR) stages those same prefix-relative locations for packaging. `--binary /absolute/built/swiftjli-cli` avoids a rebuild and verifies `--version` against VERSION before writing. `--scratch-path` selects a build directory; `--disable-package-sandbox` is only an explicit workaround for nested sandbox restrictions. An existing destination symlink/directory is refused. Merely copying the executable does not install its manual.

## Exit codes and validation

| Exit code | Meaning |
| --- | --- |
| `0` | Operation succeeded, or `--help` / `--version` completed |
| `2` | Invalid command, option or option value (`invalidArgument` or parser rejection) |
| `3` | Malformed or truncated input stream (`malformedInput`) |
| `4` | Unsupported format, feature, image layout or required backend (`unsupportedFormat`, `unsupportedFeature`, `incompatibleImageLayout`, `backendUnavailable`) |
| `5` | Resource limit or deadline exceeded (`resourceLimitExceeded`) |
| `6` | Input/output failure, existing output without `--overwrite`, or broken output pipe (`storageUnavailable`, `ioFailure`) |
| `7` | Unexpected internal failure (`internalFailure`) |
| `130` | Operation cancelled (`CancellationError` or `SIGINT`/`SIGTERM`) |

`Scripts/test-cli.py --binary /absolute/built/swiftjli-cli --output /new/evidence/directory` checks the real executable, help, verbosity, JSON separation, `encode`/`decode`/`inspect`/`validate`, NRRD and Netpbm round-trips, shell pipes, overwrite refusal, malformed/unsupported/resource/I/O/cancellation exit codes, closed pipes and staged manual install/update/rendering.
