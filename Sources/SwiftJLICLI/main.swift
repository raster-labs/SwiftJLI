// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private let tool = "swiftjli-cli"
private let version = "1.1.0-dev.2"
// PLAT-01/02 fix the Apple deployment minimum at 26.0; contract 0.5.0 reversed the
// 0.4.0 raise to 27.0 and contract 0.9.0 confirmed 26.0. Reported in one place so the
// help text and the JSON payload cannot drift apart from each other again.
private let minimumAppleOS = "26.0"
private let allCommands: Set<String> = ["capabilities", "encode", "decode", "inspect", "validate"]

private let interrupted = Atomic<Bool>(false)

private func handleTerminationSignal(_: Int32) {
    interrupted.store(true, ordering: .relaxed)
}

private func installSignalHandlers() {
    _ = signal(SIGPIPE, SIG_IGN)
    var action = sigaction()
    #if canImport(Darwin)
    action.__sigaction_u.__sa_handler = handleTerminationSignal
    #else
    action.__sigaction_handler.sa_handler = handleTerminationSignal
    #endif
    sigemptyset(&action.sa_mask)
    action.sa_flags = 0 // Do not set SA_RESTART so blocking pipe/poll operations wake with EINTR.
    _ = sigaction(SIGINT, &action, nil)
    _ = sigaction(SIGTERM, &action, nil)
}

private struct UsageError: Error { let message: String }
private struct FileIOError: Error { let message: String }

// MARK: -Checked Arithmetic & Command-Wide Execution Context

private func cliCheckedAdd(_ a: Int, _ b: Int, limitError: Bool = false) throws -> Int {
    let (value, overflow) = a.addingReportingOverflow(b)
    guard !overflow else {
        throw CodecError(limitError ? .resourceLimitExceeded : .invalidArgument, "Arithmetic overflow.")
    }
    return value
}

private func cliCheckedMultiply(_ a: Int, _ b: Int, limitError: Bool = false) throws -> Int {
    let (value, overflow) = a.multipliedReportingOverflow(by: b)
    guard !overflow else {
        throw CodecError(limitError ? .resourceLimitExceeded : .invalidArgument, "Arithmetic overflow.")
    }
    return value
}

private struct CommandExecutionContext: Sendable {
    let started: ContinuousClock.Instant
    let baseLimits: ResourceLimits

    init(limits: ResourceLimits, started: ContinuousClock.Instant = .now) {
        self.started = started
        self.baseLimits = limits
    }

    func elapsedSeconds() -> Double {
        let components = started.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    func remainingSeconds() throws -> Double {
        if interrupted.load(ordering: .relaxed) {
            throw CancellationError()
        }
        let remaining = baseLimits.deadlineSeconds - elapsedSeconds()
        if remaining <= 0 {
            throw CodecError(.resourceLimitExceeded, "CLI command deadline exceeded.")
        }
        try Task.checkCancellation()
        return remaining
    }

    func check() throws {
        _ = try remainingSeconds()
    }

    func scopedLimits(reservedBytes: Int = 0) throws -> ResourceLimits {
        let remaining = try remainingSeconds()
        guard reservedBytes >= 0, reservedBytes < baseLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Operation exceeds the configured --max-memory ceiling.")
        }
        let availableMemory = baseLimits.maximumMemoryBytes - reservedBytes
        return try ResourceLimits(
            maximumCompressedBytes: min(baseLimits.maximumCompressedBytes, availableMemory),
            maximumDecodedBytes: min(baseLimits.maximumDecodedBytes, availableMemory),
            maximumWorkspaceBytes: min(baseLimits.maximumWorkspaceBytes, availableMemory),
            maximumPixels: baseLimits.maximumPixels,
            maximumDimension: baseLimits.maximumDimension,
            maximumFrames: baseLimits.maximumFrames,
            maximumMetadataBytes: min(baseLimits.maximumMetadataBytes, availableMemory),
            maximumICCBytes: min(baseLimits.maximumICCBytes, availableMemory),
            maximumNestingDepth: baseLimits.maximumNestingDepth,
            maximumWorkers: baseLimits.maximumWorkers,
            deadlineSeconds: remaining,
            maximumMemoryBytes: availableMemory
        )
    }
}

private struct Options: Sendable {
    var command: String? = nil
    var help = false
    var version = false
    var json = false
    var quiet = false
    var verbosity = 0
    var codecOptions = false
    var overwrite = false
    var inputPath: String? = nil
    var outputPath: String? = nil
    var inputFormat: String? = nil
    var outputFormat: String? = nil
    var mode: String? = nil
    var maxError: String? = nil
    var predictor: String? = nil
    var restartInterval: String? = nil
    var quality: String? = nil
    var subsampling: String? = nil
    var progressive: String? = nil
    var backend: String? = nil
    var copyPolicy: String? = nil
    var threads: String? = nil
    var maxMemory: String? = nil
    var timeout: String? = nil
}

private func parse(_ args: [String]) throws -> Options {
    var options = Options()
    var index = 0
    var positionalOnly = false
    func level(_ value: String) throws -> Int {
        let number: Int?
        if !value.isEmpty && value.allSatisfy({ $0 == "+" }) { number = value.count }
        else if !value.isEmpty && value.utf8.allSatisfy({ (48...57).contains($0) }) { number = Int(value) }
        else { number = nil }
        guard let number, (1...5).contains(number) else {
            throw UsageError(message: "Verbosity must be 1 through 5, or + through +++++.")
        }
        return number
    }
    func consumeValue() throws -> String {
        guard index + 1 < args.count else {
            throw UsageError(message: "An option is missing its value. Use --help for syntax.")
        }
        let next = args[index + 1]
        let isNegativeNumber = next.count > 1 && next.first == "-" && next.dropFirst().first?.isNumber == true
        guard next == "-" || isNegativeNumber || !next.hasPrefix("-") else {
            throw UsageError(message: "An option is missing its value. Use --help for syntax.")
        }
        index += 1
        return next
    }
    func consumeUnique(_ current: String?, _ name: String) throws -> String {
        guard current == nil else {
            throw UsageError(message: "Duplicate option \(name). Use --help for syntax.")
        }
        options.codecOptions = true
        return try consumeValue()
    }
    while index < args.count {
        let arg = args[index]
        if !positionalOnly && arg == "--" { positionalOnly = true }
        else if !positionalOnly && ["-h", "--help"].contains(arg) { options.help = true }
        else if !positionalOnly && arg == "--version" { options.version = true }
        else if !positionalOnly && arg == "--json" { options.json = true }
        else if !positionalOnly && ["-q", "--quiet"].contains(arg) { options.quiet = true }
        else if !positionalOnly && ["-v", "--verbose", "-verbose"].contains(arg) {
            if index + 1 < args.count,
               let first = args[index + 1].first, first.isNumber || first == "+" {
                index += 1; options.verbosity = try level(args[index])
            } else { options.verbosity += 1 }
        } else if !positionalOnly,
                  let prefix = ["--verbose=", "--verbose:", "-verbose=", "-verbose:"].first(where: { arg.hasPrefix($0) }) {
            let attached = String(arg.dropFirst(prefix.count))
            options.verbosity = try level(attached.isEmpty ? consumeValue() : attached)
        } else if !positionalOnly && arg.hasPrefix("-v") && arg.count > 2 && arg.dropFirst().allSatisfy({ $0 == "v" }) {
            options.verbosity += arg.count - 1
        } else if !positionalOnly && (arg == "--input" || arg == "-i") {
            options.inputPath = try consumeUnique(options.inputPath, "--input")
        } else if !positionalOnly && (arg == "--output" || arg == "-o") {
            options.outputPath = try consumeUnique(options.outputPath, "--output")
        } else if !positionalOnly && arg == "--input-format" {
            options.inputFormat = try consumeUnique(options.inputFormat, "--input-format")
        } else if !positionalOnly && arg == "--output-format" {
            options.outputFormat = try consumeUnique(options.outputFormat, "--output-format")
        } else if !positionalOnly && arg == "--mode" {
            options.mode = try consumeUnique(options.mode, "--mode")
        } else if !positionalOnly && arg == "--max-error" {
            options.maxError = try consumeUnique(options.maxError, "--max-error")
        } else if !positionalOnly && arg == "--predictor" {
            options.predictor = try consumeUnique(options.predictor, "--predictor")
        } else if !positionalOnly && arg == "--restart-interval" {
            options.restartInterval = try consumeUnique(options.restartInterval, "--restart-interval")
        } else if !positionalOnly && arg == "--quality" {
            options.quality = try consumeUnique(options.quality, "--quality")
        } else if !positionalOnly && arg == "--subsampling" {
            options.subsampling = try consumeUnique(options.subsampling, "--subsampling")
        } else if !positionalOnly && arg == "--progressive" {
            options.progressive = try consumeUnique(options.progressive, "--progressive")
        } else if !positionalOnly && arg == "--backend" {
            options.backend = try consumeUnique(options.backend, "--backend")
        } else if !positionalOnly && arg == "--copy-policy" {
            options.copyPolicy = try consumeUnique(options.copyPolicy, "--copy-policy")
        } else if !positionalOnly && arg == "--threads" {
            options.threads = try consumeUnique(options.threads, "--threads")
        } else if !positionalOnly && arg == "--max-memory" {
            options.maxMemory = try consumeUnique(options.maxMemory, "--max-memory")
        } else if !positionalOnly && arg == "--timeout" {
            options.timeout = try consumeUnique(options.timeout, "--timeout")
        } else if !positionalOnly && arg == "--overwrite" {
            options.overwrite = true
            options.codecOptions = true
        } else if !positionalOnly && arg.hasPrefix("-") {
            throw UsageError(message: "Unknown option. Use \(tool) --help.")
        } else if options.command == nil { options.command = arg }
        else if options.command == "help" && !options.help { options.command = arg; options.help = true }
        else { throw UsageError(message: "Unexpected positional argument. Use --input or --output for codec commands.") }
        guard options.verbosity <= 5 else { throw UsageError(message: "Verbosity exceeds the maximum level 5.") }
        index += 1
    }
    if options.command == "help" { options.command = nil; options.help = true }
    if options.command == "version" { options.command = nil; options.version = true }
    if let command = options.command, !allCommands.contains(command) {
        throw UsageError(message: "Unknown command. Use \(tool) --help.")
    }
    if options.quiet && options.verbosity > 0 { throw UsageError(message: "--quiet and verbosity cannot be combined.") }
    if options.version && (options.command != nil || options.codecOptions || options.json) {
        throw UsageError(message: "--version cannot be combined with a command or command options.")
    }
    if options.codecOptions && (options.command == nil || options.command == "capabilities") {
        throw UsageError(message: "Input/output and codec options require a codec command.")
    }
    if options.json && options.command == nil { throw UsageError(message: "--json requires capabilities or a codec command.") }
    return options
}

private func help(_ command: String?) -> String {
    let common = """
    OPTIONS
      -h, --help                 Show this help; also: help [command].
      --version                  Show the development version.
      -v, -vv ... -vvvvv         Increase verbosity (maximum 5).
      --verbose LEVEL           Set verbosity to 1..5 or + through +++++.
      --verbose=LEVEL            Equivalent explicit form; -verbose: LEVEL is accepted.
      -q, --quiet                Suppress optional diagnostics; errors remain visible.

    VERBOSITY (stderr only; default 0)
      1 summary; 2 command stages; 3 capability/descriptor details; 4 elapsed timing;
      5 bounded diagnostic trace. Levels are cumulative. Quiet conflicts with verbosity.
      Payload bytes, metadata, raw addresses and input/output paths are never logged.

    EXIT STATUS
      0 success/help/version; 2 invalid usage or argument; 3 malformed/truncated input;
      4 unsupported format/feature/layout/backend; 5 resource limit or deadline exceeded;
      6 input/output failure, existing destination without --overwrite, or closed pipe;
      7 internal failure; 130 cancelled.

    MANUAL
      man \(tool) (installed with the executable by Scripts/install-cli.sh).
    """
    if let command {
        switch command {
        case "capabilities":
            return """
            USAGE: \(tool) capabilities [--json] [OPTIONS]

            Report this library's current encode/decode/inspect support without reading files.
            --json writes one JSON document to stdout; diagnostics stay on stderr.

            \(common)

            EXAMPLES
              \(tool) capabilities --json
              \(tool) capabilities --verbose=+++
            """ + "\n"
        case "encode":
            return """
            USAGE: \(tool) encode -i <path|-> -o <path|-> [OPTIONS]

            Encode an uncompressed image (NRRD or binary Netpbm PGM/PPM/PNM) to a JPEG stream.
            When reading from '-' or writing to '-', or when a path lacks a recognised extension
            (.nrrd, .pgm, .ppm, .pnm, .jpg, .jpeg), --input-format or --output-format is required.
            Binary output written to '-' goes exclusively to stdout; --json writes the operation
            report to stderr so binary stdout is never contaminated.

            CODEC OPTIONS
              -i, --input PATH           Source file or '-' for standard input.
              -o, --output PATH          Target JPEG file or '-' for standard output.
              --input-format FORMAT      Explicit source format: nrrd, pgm, ppm, pnm.
              --output-format FORMAT     Explicit target format: jpeg (or jpg).
              --mode MODE                lossless (default), near-lossless or lossy.
              --max-error N              Maximum absolute error for near-lossless point transform.
              --predictor N              Lossless predictor 1..7 (default 1).
              --restart-interval N       Restart interval in MCUs 0..65535 (default 0).
              --quality N                Lossy DCT quality 0..100 (default 90; requires --mode lossy).
              --subsampling MODE         Lossy chroma subsampling: 444, 422, 420, greyscale.
              --progressive MODE         Lossy scan mode: sequential, spectral-selection,
                                         or successive-approximation.
              --backend NAME             automatic (default), scalar, accelerated,
                                         preferred-scalar, or preferred-accelerated.
              --copy-policy POLICY       require-sharing (default) or allow-copy.
              --threads N                Maximum worker count (>= 1).
              --max-memory BYTES         Maximum operation memory budget in bytes.
              --timeout SECONDS          Command-wide deadline in seconds.
              --overwrite                Permit atomic replacement of an existing output file.
              --json                     Write structured JSON operation report to stderr.

            \(common)
            """ + "\n"
        case "decode":
            return """
            USAGE: \(tool) decode -i <path|-> -o <path|-> [OPTIONS]

            Decode a JPEG stream into a fidelity-preserving uncompressed container:
              - nrrd: 2D greyscale UInt16 with full 16-bit precision (NRRD0004 raw).
              - pgm:  Binary Netpbm P5 greyscale with exact maxval (1 << bits) - 1 (2..16 bits).
              - ppm:  Binary Netpbm P6 RGB with exact maxval (1 << bits) - 1 (2..16 bits).
              - pnm:  Binary Netpbm P5 (greyscale) or P6 (RGB) matching source components.
            Decoding fails with exit status 4 before creating output if the target format cannot
            preserve the decoded precision, component layout, or embedded ICC/Exif metadata.

            CODEC OPTIONS
              -i, --input PATH           Source JPEG file or '-' for standard input.
              -o, --output PATH          Target file or '-' for standard output.
              --input-format FORMAT      Explicit source format: jpeg (or jpg).
              --output-format FORMAT     Explicit target format: nrrd, pgm, ppm, pnm.
              --backend NAME             automatic (default), scalar, accelerated,
                                         preferred-scalar, or preferred-accelerated.
              --copy-policy POLICY       require-sharing (default) or allow-copy.
              --threads N                Maximum worker count (>= 1).
              --max-memory BYTES         Maximum operation memory budget in bytes.
              --timeout SECONDS          Command-wide deadline in seconds.
              --overwrite                Permit atomic replacement of an existing output file.
              --json                     Write structured JSON operation report to stderr.

            \(common)
            """ + "\n"
        case "inspect", "validate":
            let summary = command == "inspect"
                ? "Inspect JPEG container and frame headers without decoding entropy scans."
                : "Validate the full JPEG stream and entropy-coded scan data without writing image output."
            return """
            USAGE: \(tool) \(command) -i <path|-> [--json] [OPTIONS]

            \(summary)
            When reading from '-' or a path without a .jpg/.jpeg extension, pass --input-format jpeg.
            --json writes one structured JSON object to stdout; diagnostics stay on stderr.

            CODEC OPTIONS
              -i, --input PATH           Source JPEG file or '-' for standard input.
              --input-format FORMAT      Explicit source format: jpeg (or jpg).
              --backend NAME             automatic (default), scalar, accelerated,
                                         preferred-scalar, or preferred-accelerated.
              --copy-policy POLICY       require-sharing (default) or allow-copy.
              --threads N                Maximum worker count (>= 1).
              --max-memory BYTES         Maximum operation memory budget in bytes.
              --timeout SECONDS          Command-wide deadline in seconds.
              --json                     Write structured JSON report to stdout.

            \(common)
            """ + "\n"
        default:
            break
        }
    }
    return """
    \(tool) \(version) — JPEG including native lossless JPEG
    USAGE: \(tool) [OPTIONS] <command> [OPTIONS]

    COMMANDS
      capabilities [--json]      Report actual library support.
      encode -i PATH -o PATH     Encode NRRD or PGM/PPM/PNM input to JPEG.
      decode -i PATH -o PATH     Decode JPEG input to NRRD or PGM/PPM/PNM.
      inspect -i PATH [--json]   Inspect JPEG headers and frame descriptor.
      validate -i PATH [--json]  Validate full JPEG stream and entropy scans.
      help [command]             Show global or command-specific help.
      version                    Show the development version.
      transcode                  Unavailable in \(tool) (exit 2).

    Builds with Swift 6.2 or later; Apple OS baseline \(minimumAppleOS). CLI hosts: macOS/Linux.

    \(common)

    EXAMPLES
      \(tool) -h
      \(tool) capabilities --json
      \(tool) inspect -i image.jpg --json
      \(tool) validate -i image.jpg
      \(tool) decode -i image.jpg -o image.nrrd
      \(tool) encode -i image.nrrd -o image.jpg --mode lossless
    """ + "\n"
}

private func write(_ text: String, to handle: FileHandle) throws {
    try handle.write(contentsOf: Data(text.utf8))
}

private func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try handle.write(contentsOf: data + Data([10]))
}

// MARK: - Option & Format Validation

private enum CanonicalFormat: String, Sendable {
    case jpeg, nrrd, pgm, ppm, pnm
}

private let knownUnsupportedFormats: Set<String> = [
    "raw", "bin", "png", "tif", "tiff", "bmp", "gif", "webp", "avif", "heic", "heif",
    "jls", "jpegls", "jpeg-ls", "j2k", "jp2", "jpx", "jph", "htj2k", "jpeg2000", "jpeg-2000",
    "jxl", "jpegxl", "jpeg-xl", "dcm", "dicom", "pam", "pbm"
]

private func classifyFormatName(_ name: String) throws -> CanonicalFormat {
    let lower = name.lowercased()
    switch lower {
    case "jpeg", "jpg": return .jpeg
    case "nrrd": return .nrrd
    case "pgm": return .pgm
    case "ppm": return .ppm
    case "pnm": return .pnm
    default:
        if knownUnsupportedFormats.contains(lower) {
            throw CodecError(.unsupportedFormat, "Unsupported format.")
        }
        throw UsageError(message: "Unrecognised format name. Supported formats: jpeg, nrrd, pgm, ppm, pnm.")
    }
}

private func classifyPathExtension(_ path: String) throws -> CanonicalFormat? {
    guard path != "-" else { return nil }
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    guard !ext.isEmpty else { return nil }
    switch ext {
    case "jpg", "jpeg": return .jpeg
    case "nrrd": return .nrrd
    case "pgm": return .pgm
    case "ppm": return .ppm
    case "pnm": return .pnm
    default:
        if knownUnsupportedFormats.contains(ext) {
            throw CodecError(.unsupportedFormat, "Unsupported file format extension.")
        }
        return nil
    }
}

private func resolveInputFormat(path: String, explicit: String?, command: String) throws -> CanonicalFormat {
    let extFormat = try classifyPathExtension(path)
    let resolved: CanonicalFormat
    if let explicit {
        let exp = try classifyFormatName(explicit)
        if let extFormat, extFormat != exp {
            throw CodecError(.malformedInput, "Declared --input-format conflicts with input file extension.")
        }
        resolved = exp
    } else if let extFormat {
        resolved = extFormat
    } else {
        throw UsageError(message: "--input-format is required when reading from '-' or a path without a recognised extension.")
    }
    if command == "encode" {
        guard resolved != .jpeg else {
            throw CodecError(.unsupportedFormat, "encode requires an uncompressed input format (nrrd, pgm, ppm, pnm).")
        }
    } else {
        guard resolved == .jpeg else {
            throw CodecError(.unsupportedFormat, "\(command) requires JPEG input.")
        }
    }
    return resolved
}

private func resolveOutputFormat(path: String, explicit: String?, command: String) throws -> CanonicalFormat {
    let extFormat = try classifyPathExtension(path)
    let resolved: CanonicalFormat
    if let explicit {
        let exp = try classifyFormatName(explicit)
        if let extFormat, extFormat != exp {
            throw UsageError(message: "Declared --output-format conflicts with output file extension.")
        }
        resolved = exp
    } else if let extFormat {
        resolved = extFormat
    } else {
        throw UsageError(message: "--output-format is required when writing to '-' or a path without a recognised extension.")
    }
    if command == "encode" {
        guard resolved == .jpeg else {
            throw CodecError(.unsupportedFormat, "encode outputs JPEG only.")
        }
    } else if command == "decode" {
        guard resolved != .jpeg else {
            throw CodecError(.unsupportedFormat, "decode requires an uncompressed output format (nrrd, pgm, ppm, pnm).")
        }
    }
    return resolved
}

private func buildResourceLimits(_ options: Options) throws -> ResourceLimits {
    let base = ResourceLimits.default
    var workers = base.maximumWorkers
    if let rawThreads = options.threads {
        guard let parsed = Int(rawThreads), parsed >= 1 else {
            throw UsageError(message: "--threads must be a positive integer.")
        }
        workers = parsed
    }
    var deadline = base.deadlineSeconds
    if let rawTimeout = options.timeout {
        guard let parsed = Double(rawTimeout), parsed.isFinite, parsed > 0 else {
            throw UsageError(message: "--timeout must be a positive finite number of seconds.")
        }
        deadline = parsed
    }
    var memory = base.maximumMemoryBytes
    if let rawMemory = options.maxMemory {
        guard let parsed = Int(rawMemory), parsed > 0 else {
            throw UsageError(message: "--max-memory must be a positive integer byte count.")
        }
        memory = parsed
    }
    return try ResourceLimits(
        maximumCompressedBytes: min(base.maximumCompressedBytes, memory),
        maximumDecodedBytes: min(base.maximumDecodedBytes, memory),
        maximumWorkspaceBytes: min(base.maximumWorkspaceBytes, memory),
        maximumPixels: base.maximumPixels,
        maximumDimension: base.maximumDimension,
        maximumFrames: base.maximumFrames,
        maximumMetadataBytes: min(base.maximumMetadataBytes, memory),
        maximumICCBytes: min(base.maximumICCBytes, memory),
        maximumNestingDepth: base.maximumNestingDepth,
        maximumWorkers: workers,
        deadlineSeconds: deadline,
        maximumMemoryBytes: memory
    )
}

private func buildExecutionPolicy(_ raw: String?) throws -> ExecutionPolicy {
    guard let raw else { return .automatic }
    switch raw.lowercased() {
    case "automatic", "auto": return .automatic
    case "scalar", "scalar-cpu", "scalarcpu": return .required(.scalarCPU)
    case "accelerated", "accelerate", "simd": return .required(.accelerated)
    case "preferred-scalar", "preferred-scalar-cpu": return .preferred(.scalarCPU)
    case "preferred-accelerated", "preferred-accelerate", "preferred-simd": return .preferred(.accelerated)
    case "metal", "preferred-metal":
        throw CodecError(.backendUnavailable, "Requested backend is unavailable in SwiftJLI.")
    default:
        throw UsageError(message: "Invalid --backend value. Use automatic, scalar, accelerated, preferred-scalar, or preferred-accelerated.")
    }
}

private func buildCopyPolicy(_ raw: String?) throws -> CopyPolicy {
    guard let raw else { return .requireSharedStorage }
    switch raw.lowercased() {
    case "require-sharing", "require-shared-storage": return .requireSharedStorage
    case "allow-copy": return .allowCopy
    default:
        throw UsageError(message: "Invalid --copy-policy value. Use require-sharing or allow-copy.")
    }
}

private func buildEncoderConfiguration(_ options: Options) throws -> EncoderConfiguration {
    let modeName = (options.mode ?? "lossless").lowercased()
    let mode: CompressionMode
    switch modeName {
    case "lossless":
        if let rawMaxError = options.maxError {
            guard let maxErr = Int(rawMaxError), maxErr == 0 else {
                throw UsageError(message: "--max-error requires --mode near-lossless when non-zero.")
            }
        }
        mode = .lossless
    case "near-lossless":
        guard let rawMaxError = options.maxError, let maxErr = Int(rawMaxError) else {
            throw UsageError(message: "--mode near-lossless requires an integer --max-error.")
        }
        guard maxErr > 0 else {
            throw CodecError(.invalidArgument, "Near-lossless --max-error must be positive.")
        }
        mode = .nearLossless(maximumAbsoluteError: maxErr)
    case "lossy":
        if options.maxError != nil {
            throw UsageError(message: "--max-error cannot be combined with --mode lossy.")
        }
        mode = .lossy
    default:
        throw UsageError(message: "Invalid --mode value. Use lossless, near-lossless, or lossy.")
    }

    var predictor = 1
    if let rawPred = options.predictor {
        let cleaned = rawPred.lowercased().hasPrefix("p") ? String(rawPred.dropFirst()) : rawPred
        guard let parsed = Int(cleaned), (1...7).contains(parsed) else {
            throw CodecError(.invalidArgument, "Predictor must be 1 through 7.")
        }
        predictor = parsed
    }

    var restartInterval = 0
    if let rawRestart = options.restartInterval {
        guard let parsed = Int(rawRestart), (0...65535).contains(parsed) else {
            throw CodecError(.invalidArgument, "Restart interval must be 0 through 65535.")
        }
        restartInterval = parsed
    }

    var dct = DCTOptions()
    if mode == .lossy {
        var quality = dct.quality
        if let rawQuality = options.quality {
            guard let parsed = Double(rawQuality), parsed.isFinite, (0...100).contains(parsed) else {
                throw CodecError(.invalidArgument, "Quality must be between 0 and 100.")
            }
            quality = parsed
        }
        var subsampling = dct.chromaSubsampling
        if let rawSub = options.subsampling {
            switch rawSub.lowercased() {
            case "444", "4:4:4", "yuv444": subsampling = .yuv444
            case "422", "4:2:2", "yuv422": subsampling = .yuv422
            case "420", "4:2:0", "yuv420": subsampling = .yuv420
            case "greyscale", "grayscale", "400", "4:0:0": subsampling = .greyscale
            default:
                throw UsageError(message: "Invalid --subsampling value. Use 444, 422, 420, or greyscale.")
            }
        }
        var progressive = dct.progressiveMode
        if let rawProg = options.progressive {
            switch rawProg.lowercased() {
            case "sequential", "none", "false": progressive = .sequential
            case "spectral-selection", "spectral": progressive = .spectralSelection
            case "successive-approximation", "progressive", "true": progressive = .successiveApproximation
            default:
                throw UsageError(message: "Invalid --progressive value. Use sequential, spectral-selection, or successive-approximation.")
            }
        }
        dct = DCTOptions(quality: quality, chromaSubsampling: subsampling, progressiveMode: progressive)
    } else if options.quality != nil || options.subsampling != nil || options.progressive != nil {
        throw UsageError(message: "DCT options (--quality, --subsampling, --progressive) require --mode lossy.")
    }

    return try EncoderConfiguration(
        mode: mode,
        codecOptions: CodecOptions(predictor: predictor, restartInterval: restartInterval, dct: dct)
    )
}

// MARK: - Bounded & Deadline-Enforced Nonblocking File/Pipe I/O

private func withNonBlockingDescriptor<R>(_ fd: Int32, enabled: Bool, _ body: () throws -> R) throws -> R {
    guard enabled else { return try body() }
    let originalFlags = fcntl(fd, F_GETFL, 0)
    guard originalFlags >= 0 else {
        throw FileIOError(message: "stream I/O failure: unable to query descriptor flags.")
    }
    let needsChange = (originalFlags & O_NONBLOCK) == 0
    if needsChange {
        guard fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            throw FileIOError(message: "stream I/O failure: unable to configure nonblocking descriptor.")
        }
    }
    defer {
        if needsChange {
            _ = fcntl(fd, F_SETFL, originalFlags)
        }
    }
    return try body()
}

private func waitForDescriptor(_ fd: Int32, event: Int16, context: CommandExecutionContext) throws {
    while true {
        let remaining = try context.remainingSeconds()
        let timeoutMs = Int32(max(1.0, min(25.0, ceil(remaining * 1000.0))))
        var pfd = pollfd(fd: fd, events: event, revents: 0)
        let rc = poll(&pfd, 1, timeoutMs)
        if rc > 0 {
            return
        }
        if rc < 0 && errno != EINTR {
            throw FileIOError(message: "I/O failure while waiting on stream descriptor.")
        }
        try context.check()
    }
}

private func preflightOutputDestination(_ path: String, overwrite: Bool, context: CommandExecutionContext) throws {
    try context.check()
    guard path != "-" else { return }
    guard !path.isEmpty else {
        throw UsageError(message: "Output path must not be empty.")
    }
    var st = stat()
    if lstat(path, &st) == 0 {
        let fileType = st.st_mode & S_IFMT
        guard fileType == S_IFREG else {
            throw FileIOError(message: "output I/O failure: refusing to write to non-regular file or symbolic link.")
        }
        guard overwrite else {
            throw FileIOError(message: "output I/O failure: destination already exists (pass --overwrite to replace).")
        }
    } else if errno != ENOENT {
        throw FileIOError(message: "output I/O failure: unable to inspect output destination.")
    }
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    var parentStat = stat()
    guard stat(parent, &parentStat) == 0, (parentStat.st_mode & S_IFMT) == S_IFDIR else {
        throw FileIOError(message: "output I/O failure: destination directory does not exist.")
    }
}

private func readBoundedInput(from path: String, maximumBytes: Int, context: CommandExecutionContext) throws -> Data {
    try context.check()
    guard !path.isEmpty else {
        throw UsageError(message: "Input path must not be empty.")
    }
    let fd: Int32
    let closeWhenDone: Bool
    let isStream: Bool
    if path == "-" {
        fd = STDIN_FILENO
        closeWhenDone = false
        isStream = true
    } else {
        var st = stat()
        guard stat(path, &st) == 0 else {
            throw FileIOError(message: "input I/O failure: unable to open input file.")
        }
        let fileType = st.st_mode & S_IFMT
        guard fileType != S_IFDIR else {
            throw FileIOError(message: "input I/O failure: input path is a directory.")
        }
        guard fileType == S_IFREG else {
            throw FileIOError(message: "input I/O failure: named non-regular inputs are unsupported (use '-' for standard input).")
        }
        if st.st_size > Int64(maximumBytes) {
            throw CodecError(.resourceLimitExceeded, "Input file size exceeds the configured memory budget.")
        }
        fd = open(path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else {
            throw FileIOError(message: "input I/O failure: unable to open input file.")
        }
        var openedStat = stat()
        guard fstat(fd, &openedStat) == 0, (openedStat.st_mode & S_IFMT) == S_IFREG else {
            _ = close(fd)
            throw FileIOError(message: "input I/O failure: opened input descriptor is not a regular file.")
        }
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 && (flags & O_NONBLOCK) != 0 {
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        }
        closeWhenDone = true
        isStream = false
    }
    defer {
        if closeWhenDone { _ = close(fd) }
    }

    return try withNonBlockingDescriptor(fd, enabled: isStream) {
        var buffer = Data()
        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while true {
            try context.check()
            let count = chunk.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                #if canImport(Darwin)
                return Darwin.read(fd, base, chunkSize)
                #else
                return Glibc.read(fd, base, chunkSize)
                #endif
            }
            if count > 0 {
                let newCount = try cliCheckedAdd(buffer.count, count, limitError: true)
                if newCount > maximumBytes {
                    throw CodecError(.resourceLimitExceeded, "Input stream exceeds the configured memory budget.")
                }
                buffer.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                break
            } else {
                if errno == EINTR {
                    try context.check()
                    continue
                }
                if isStream && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try waitForDescriptor(fd, event: Int16(POLLIN), context: context)
                    continue
                }
                throw FileIOError(message: "input I/O failure: read error.")
            }
        }
        try context.check()
        return buffer
    }
}

private func writeAllDescriptor(_ fd: Int32, data: Data, isStream: Bool, context: CommandExecutionContext) throws {
    try withNonBlockingDescriptor(fd, enabled: isStream) {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                try context.check()
                let chunkLength = min(64 * 1024, raw.count - offset)
                let written: Int
                #if canImport(Darwin)
                written = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), chunkLength)
                #else
                written = Glibc.write(fd, raw.baseAddress!.advanced(by: offset), chunkLength)
                #endif
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    try context.check()
                    continue
                } else if written < 0 && isStream && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try waitForDescriptor(fd, event: Int16(POLLOUT), context: context)
                    continue
                } else {
                    throw FileIOError(message: "output I/O failure: failed writing output stream.")
                }
            }
        }
    }
}

private func writeOutputAtomically(_ data: Data, to path: String, overwrite: Bool, context: CommandExecutionContext) throws {
    try context.check()
    if path == "-" {
        try writeAllDescriptor(STDOUT_FILENO, data: data, isStream: true, context: context)
        return
    }
    try preflightOutputDestination(path, overwrite: overwrite, context: context)
    let destinationURL = URL(fileURLWithPath: path)
    let directoryURL = destinationURL.deletingLastPathComponent()
    let tempName = ".swiftjli-tmp-\(getpid())-\(UUID().uuidString)"
    let tempPath = directoryURL.appendingPathComponent(tempName).path
    let fd = open(tempPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard fd >= 0 else {
        throw FileIOError(message: "output I/O failure: unable to create temporary file in destination directory.")
    }
    var committed = false
    defer {
        if fd >= 0 { _ = close(fd) }
        if !committed { _ = unlink(tempPath) }
    }
    try writeAllDescriptor(fd, data: data, isStream: false, context: context)
    guard fsync(fd) == 0 else {
        throw FileIOError(message: "output I/O failure: failed synchronising temporary file.")
    }
    var checkStat = stat()
    if lstat(path, &checkStat) == 0 {
        let fileType = checkStat.st_mode & S_IFMT
        guard fileType == S_IFREG else {
            throw FileIOError(message: "output I/O failure: refusing to overwrite non-regular file or symbolic link.")
        }
        guard overwrite else {
            throw FileIOError(message: "output I/O failure: destination already exists (pass --overwrite to replace).")
        }
    }
    // Recheck cancellation and command-wide deadline immediately before final publication.
    try context.check()
    if overwrite {
        guard rename(tempPath, path) == 0 else {
            throw FileIOError(message: "output I/O failure: atomic rename failed.")
        }
        committed = true
    } else {
        guard link(tempPath, path) == 0 else {
            throw FileIOError(message: "output I/O failure: destination already exists or cannot be linked.")
        }
        _ = unlink(tempPath)
        committed = true
    }
}

// MARK: - NRRD & Netpbm Container Adapters (CLI-04)

private func readNRRD(_ data: Data, reservedBytes: Int, context: CommandExecutionContext) throws -> Image {
    try context.check()
    let limits = try context.scopedLimits(reservedBytes: reservedBytes)
    guard data.count >= 8 else {
        throw CodecError(.malformedInput, "Truncated or missing NRRD magic header.")
    }
    let maxHeaderBytes = min(data.count, 64 * 1024)
    var headerEnd: Int? = nil
    var payloadStart: Int? = nil
    var index = 0
    while index < maxHeaderBytes {
        if data[index] == 0 {
            throw CodecError(.malformedInput, "NRRD header contains an embedded NUL byte.")
        }
        if index + 1 < maxHeaderBytes && data[index] == 0x0A && data[index + 1] == 0x0A {
            headerEnd = index
            payloadStart = index + 2
            break
        }
        if index + 3 < maxHeaderBytes && data[index] == 0x0D && data[index + 1] == 0x0A
            && data[index + 2] == 0x0D && data[index + 3] == 0x0A {
            headerEnd = index
            payloadStart = index + 4
            break
        }
        index += 1
    }
    guard let headerEnd, let payloadStart else {
        throw CodecError(.malformedInput, "NRRD header exceeds 64 KiB or is missing its blank-line terminator.")
    }
    guard let headerString = String(data: data.subdata(in: 0..<headerEnd), encoding: .utf8) else {
        throw CodecError(.malformedInput, "NRRD header is not valid UTF-8.")
    }
    let rawLines = headerString.split(separator: "\n", omittingEmptySubsequences: false).map {
        $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
    }
    guard rawLines.count <= 128, let magic = rawLines.first else {
        throw CodecError(.malformedInput, "NRRD header line count exceeds 128 or is empty.")
    }
    guard ["NRRD0001", "NRRD0002", "NRRD0003", "NRRD0004", "NRRD0005"].contains(magic) else {
        throw CodecError(.malformedInput, "Input does not start with a supported NRRD0001..NRRD0005 magic line.")
    }

    var seenFields = Set<String>()
    var sampleType: String? = nil
    var dimension: Int? = nil
    var sizes: [Int]? = nil
    var encoding: String? = nil
    var endian: ByteOrder? = nil

    for line in rawLines.dropFirst() {
        try context.check()
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        if line.range(of: ":=") != nil {
            throw CodecError(.unsupportedFormat, "NRRD key-value metadata (:=) is not supported under strict preservation.")
        }
        guard let colon = line.firstIndex(of: ":") else {
            throw CodecError(.malformedInput, "Malformed NRRD header field line.")
        }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value.lowercased().contains("://") {
            throw CodecError(.unsupportedFormat, "External NRRD URLs are not supported.")
        }
        guard seenFields.insert(key).inserted else {
            throw CodecError(.malformedInput, "Duplicate NRRD header field.")
        }
        switch key {
        case "type":
            let lower = value.lowercased()
            if ["uint16", "ushort", "unsigned short", "uint16_t"].contains(lower) {
                sampleType = "uint16"
            } else if [
                "uchar", "uint8", "uint8_t", "unsigned char", "char", "int8", "int8_t", "signed char",
                "short", "int16", "int16_t", "signed short", "int", "int32", "int32_t", "signed int",
                "uint", "uint32", "uint32_t", "unsigned int", "longlong", "int64", "int64_t",
                "ulonglong", "uint64", "uint64_t", "float", "double", "block"
            ].contains(lower) {
                throw CodecError(.unsupportedFormat, "NRRD sample type is outside the SwiftJLI 16-bit greyscale profile.")
            } else {
                throw CodecError(.malformedInput, "Unrecognised NRRD type field.")
            }
        case "dimension":
            guard let dim = Int(value), dim > 0 else {
                throw CodecError(.malformedInput, "Invalid NRRD dimension value.")
            }
            guard dim == 2 else {
                throw CodecError(.incompatibleImageLayout, "NRRD dimension must be 2 for the SwiftJLI 2D greyscale profile.")
            }
            dimension = dim
        case "sizes":
            let tokens = value.split(whereSeparator: { $0.isWhitespace })
            var parsedSizes: [Int] = []
            for tok in tokens {
                guard let v = Int(tok), v > 0 else {
                    throw CodecError(.malformedInput, "Invalid or non-positive NRRD sizes token.")
                }
                parsedSizes.append(v)
            }
            sizes = parsedSizes
        case "encoding":
            let lower = value.lowercased()
            if lower == "raw" {
                encoding = "raw"
            } else if ["ascii", "txt", "text", "hex", "gz", "gzip", "bz2", "bzip2", "zstd"].contains(lower) {
                throw CodecError(.unsupportedFormat, "NRRD encoding is unsupported; raw encoding is required.")
            } else {
                throw CodecError(.malformedInput, "Unrecognised NRRD encoding field.")
            }
        case "endian":
            switch value.lowercased() {
            case "little": endian = .littleEndian
            case "big": endian = .bigEndian
            default: throw CodecError(.malformedInput, "NRRD endian must be little or big.")
            }
        case "kinds":
            let kindsTokens = value.lowercased().split(whereSeparator: { $0.isWhitespace })
            guard kindsTokens.count == 2,
                  kindsTokens.allSatisfy({ $0 == "domain" || $0 == "space" }) else {
                throw CodecError(.incompatibleImageLayout, "NRRD kinds must be two spatial domain axes for 2D greyscale.")
            }
        default:
            throw CodecError(.unsupportedFormat, "Unsupported NRRD header field.")
        }
    }

    guard sampleType == "uint16", let dimension, let sizes, encoding == "raw", let endian else {
        throw CodecError(.malformedInput, "NRRD header is missing required fields (type, dimension, sizes, encoding, endian).")
    }
    guard sizes.count == dimension, sizes.count == 2 else {
        throw CodecError(.incompatibleImageLayout, "NRRD sizes count does not match 2D greyscale profile.")
    }
    let width = sizes[0], height = sizes[1]
    guard width <= limits.maximumDimension, height <= limits.maximumDimension else {
        throw CodecError(.resourceLimitExceeded, "NRRD image dimensions exceed operation limits.")
    }
    let pixels = try cliCheckedMultiply(width, height, limitError: true)
    guard pixels <= limits.maximumPixels else {
        throw CodecError(.resourceLimitExceeded, "NRRD pixel count exceeds operation limits.")
    }
    let expectedBytes = try cliCheckedMultiply(pixels, 2, limitError: true)
    guard expectedBytes <= limits.maximumDecodedBytes, expectedBytes <= limits.maximumMemoryBytes else {
        throw CodecError(.resourceLimitExceeded, "NRRD decoded buffer exceeds --max-memory.")
    }
    let actualBytes = data.count - payloadStart
    guard actualBytes == expectedBytes else {
        throw CodecError(.malformedInput, "NRRD payload length does not match header dimensions.")
    }
    let descriptor = try ImageDescriptor.greyscale16(width: width, height: height, meaningfulBits: 16, limits: limits)
    let destination = try ImageDestination.allocate(descriptor: descriptor, limits: limits)
    return try destination.write { dst in
        try data.withUnsafeBytes { src in
            for y in 0..<height {
                try context.check()
                let rowStart = y * width
                for x in 0..<width {
                    let i = rowStart + x
                    let sOff = payloadStart + i * 2
                    let b0 = src[sOff]
                    let b1 = src[sOff + 1]
                    if endian == .littleEndian {
                        dst[i * 2] = b0
                        dst[i * 2 + 1] = b1
                    } else {
                        dst[i * 2] = b1
                        dst[i * 2 + 1] = b0
                    }
                }
            }
        }
    }
}

private func writeNRRD(_ image: Image, reservedBytes: Int, context: CommandExecutionContext) throws -> Data {
    try context.check()
    let limits = try context.scopedLimits(reservedBytes: reservedBytes)
    let d = image.descriptor
    guard d.colour == .greyscale, d.components == [.grey], d.planes.count == 1, d.sampleType == .unsignedInteger else {
        throw CodecError(.incompatibleImageLayout, "NRRD output supports 2D single-component unsigned integer greyscale images only.")
    }
    guard d.storageBits == 16, d.meaningfulBits == 16 else {
        throw CodecError(.unsupportedFormat, "NRRD output requires full 16-bit precision (meaningfulBits == 16); use PGM/PNM to preserve sub-16-bit precision.")
    }
    guard d.iccProfile == nil, image.metadata.entries.isEmpty else {
        throw CodecError(.unsupportedFormat, "NRRD output cannot preserve embedded ICC or Exif metadata.")
    }
    let header = "NRRD0004\ntype: uint16\ndimension: 2\nsizes: \(d.width) \(d.height)\nencoding: raw\nendian: little\n\n"
    let headerData = Data(header.utf8)
    let pixels = try cliCheckedMultiply(d.width, d.height, limitError: true)
    let payloadBytes = try cliCheckedMultiply(pixels, 2, limitError: true)
    let totalBytes = try cliCheckedAdd(headerData.count, payloadBytes, limitError: true)
    guard payloadBytes <= limits.maximumDecodedBytes, totalBytes <= limits.maximumMemoryBytes else {
        throw CodecError(.resourceLimitExceeded, "Serialised NRRD output exceeds --max-memory.")
    }
    var output = Data()
    output.reserveCapacity(totalBytes)
    output.append(headerData)
    let plane = d.planes[0]
    try image.storage.withUnsafeBytes { raw in
        for y in 0..<d.height {
            try context.check()
            for x in 0..<d.width {
                let off = plane.offset + y * plane.rowBytes + x * plane.pixelStride
                let first = raw[off]
                let second = raw[off + 1]
                if d.byteOrder == .littleEndian {
                    output.append(first)
                    output.append(second)
                } else {
                    output.append(second)
                    output.append(first)
                }
            }
        }
    }
    try context.check()
    return output
}

private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 || byte == 0x0B || byte == 0x0C
}

private func readNetpbm(
    _ data: Data, declaredFormat: CanonicalFormat, reservedBytes: Int, context: CommandExecutionContext
) throws -> Image {
    try context.check()
    let limits = try context.scopedLimits(reservedBytes: reservedBytes)
    guard data.count >= 7 else {
        throw CodecError(.malformedInput, "Truncated or missing Netpbm header.")
    }
    guard data[0] == 0x50 else { // 'P'
        throw CodecError(.malformedInput, "Input does not start with a Netpbm magic signature.")
    }
    let magicType = data[1]
    if [0x31, 0x32, 0x33, 0x34, 0x37].contains(magicType) { // P1, P2, P3, P4, P7
        if (declaredFormat == .pgm && magicType == 0x32) || (declaredFormat == .ppm && magicType == 0x33) || declaredFormat == .pnm {
            throw CodecError(.unsupportedFormat, "ASCII Netpbm and PAM formats are unsupported; binary P5/P6 is required.")
        }
        throw CodecError(.malformedInput, "Input magic does not match declared Netpbm format.")
    }
    guard magicType == 0x35 || magicType == 0x36 else { // '5' or '6'
        throw CodecError(.malformedInput, "Input does not start with binary PGM (P5) or PPM (P6) magic.")
    }
    let isPGM = (magicType == 0x35)
    if declaredFormat == .pgm && !isPGM {
        throw CodecError(.malformedInput, "Declared PGM input has PPM (P6) magic.")
    }
    if declaredFormat == .ppm && isPGM {
        throw CodecError(.malformedInput, "Declared PPM input has PGM (P5) magic.")
    }
    guard isASCIIWhitespace(data[2]) || data[2] == 0x23 else {
        throw CodecError(.malformedInput, "Netpbm magic must be followed by whitespace.")
    }

    let maxHeaderBytes = min(data.count, 64 * 1024)
    var pos = 2
    var tokens: [Int] = []
    while tokens.count < 3 {
        try context.check()
        while pos < maxHeaderBytes {
            let b = data[pos]
            if b == 0 {
                throw CodecError(.malformedInput, "Netpbm header contains an embedded NUL byte.")
            }
            if isASCIIWhitespace(b) {
                pos += 1
            } else if b == 0x23 { // '#' comment to end of line
                pos += 1
                while pos < maxHeaderBytes && data[pos] != 0x0A && data[pos] != 0x0D {
                    if data[pos] == 0 {
                        throw CodecError(.malformedInput, "Netpbm comment contains an embedded NUL byte.")
                    }
                    pos += 1
                }
            } else {
                break
            }
        }
        guard pos < maxHeaderBytes else {
            throw CodecError(.malformedInput, "Netpbm header exceeds 64 KiB or is incomplete.")
        }
        var value = 0
        var digits = 0
        while pos < maxHeaderBytes {
            let b = data[pos]
            if b >= 0x30 && b <= 0x39 {
                let digit = Int(b - 0x30)
                let (mul, o1) = value.multipliedReportingOverflow(by: 10)
                let (add, o2) = mul.addingReportingOverflow(digit)
                guard !o1 && !o2 else {
                    throw CodecError(.malformedInput, "Integer overflow in Netpbm header token.")
                }
                value = add
                digits += 1
                pos += 1
            } else if isASCIIWhitespace(b) || (tokens.count < 2 && b == 0x23) {
                break
            } else {
                throw CodecError(.malformedInput, "Invalid character in Netpbm header token.")
            }
        }
        guard digits > 0 else {
            throw CodecError(.malformedInput, "Missing integer token in Netpbm header.")
        }
        tokens.append(value)
    }

    guard pos < maxHeaderBytes, isASCIIWhitespace(data[pos]) else {
        throw CodecError(.malformedInput, "Netpbm maxval must be followed by a single whitespace byte.")
    }
    let rasterStart = pos + 1

    let width = tokens[0], height = tokens[1], maxval = tokens[2]
    guard width > 0, height > 0, (1...65535).contains(maxval) else {
        throw CodecError(.malformedInput, "Netpbm width, height, and maxval must be positive and within bounds.")
    }
    guard maxval >= 3, ((maxval + 1) & maxval) == 0 else {
        throw CodecError(.unsupportedFormat, "Netpbm maxval does not match an exact 2..16-bit precision ((1 << bits) - 1).")
    }
    let bits = Int.bitWidth - (maxval + 1).leadingZeroBitCount - 1
    guard (2...16).contains(bits) else {
        throw CodecError(.unsupportedFormat, "Netpbm precision is outside the supported 2..16-bit range.")
    }

    // Checked dimension & byte-count admission before any descriptor or buffer allocation.
    guard width <= limits.maximumDimension, height <= limits.maximumDimension else {
        throw CodecError(.resourceLimitExceeded, "Netpbm dimensions exceed operation limits.")
    }
    let pixels = try cliCheckedMultiply(width, height, limitError: true)
    guard pixels <= limits.maximumPixels else {
        throw CodecError(.resourceLimitExceeded, "Netpbm pixel count exceeds operation limits.")
    }
    let components = isPGM ? 1 : 3
    let bps = bits <= 8 ? 1 : 2
    let rowSamples = try cliCheckedMultiply(width, components)
    let rowBytes = try cliCheckedMultiply(rowSamples, bps)
    let expectedBytes = try cliCheckedMultiply(rowBytes, height, limitError: true)
    let sampleCount = try cliCheckedMultiply(pixels, components, limitError: true)
    guard expectedBytes <= limits.maximumDecodedBytes, expectedBytes <= limits.maximumMemoryBytes else {
        throw CodecError(.resourceLimitExceeded, "Netpbm decoded buffer exceeds --max-memory.")
    }

    let actualBytes = data.count - rasterStart
    guard actualBytes == expectedBytes else {
        throw CodecError(.malformedInput, "Netpbm payload length does not match header dimensions.")
    }

    let plane = try PlaneDescriptor(
        width: width, height: height, components: Array(0..<components),
        offset: 0, sampleStride: bps, pixelStride: components * bps,
        rowBytes: rowBytes, byteCount: expectedBytes
    )
    let descriptor = try ImageDescriptor(
        width: width, height: height, sampleType: .unsignedInteger,
        storageBits: bps * 8, meaningfulBits: bits, byteOrder: .littleEndian,
        components: isPGM ? [.grey] : [.red, .green, .blue],
        colour: isPGM ? .greyscale : .rgb, planes: [plane], limits: limits
    )

    let destination = try ImageDestination.allocate(descriptor: descriptor, limits: limits)
    return try destination.write { dst in
        try data.withUnsafeBytes { src in
            if bps == 1 {
                let limit8 = UInt8(maxval)
                for y in 0..<height {
                    try context.check()
                    let rowBase = y * rowSamples
                    for x in 0..<rowSamples {
                        let i = rowBase + x
                        let s = src[rasterStart + i]
                        guard s <= limit8 else {
                            throw CodecError(.malformedInput, "Sample value exceeds declared Netpbm maxval.")
                        }
                        dst[i] = s
                    }
                }
            } else {
                let limit16 = UInt16(maxval)
                for y in 0..<height {
                    try context.check()
                    let rowBase = y * rowSamples
                    for x in 0..<rowSamples {
                        let i = rowBase + x
                        let sOff = rasterStart + i * 2
                        let hi = UInt16(src[sOff])
                        let lo = UInt16(src[sOff + 1])
                        let val = (hi << 8) | lo
                        guard val <= limit16 else {
                            throw CodecError(.malformedInput, "Sample value exceeds declared Netpbm maxval.")
                        }
                        dst[i * 2] = UInt8(truncatingIfNeeded: val)
                        dst[i * 2 + 1] = UInt8(val >> 8)
                    }
                }
            }
        }
        _ = sampleCount
    }
}

private func writeNetpbm(
    _ image: Image, format: CanonicalFormat, reservedBytes: Int, context: CommandExecutionContext
) throws -> Data {
    try context.check()
    let limits = try context.scopedLimits(reservedBytes: reservedBytes)
    let d = image.descriptor
    guard d.sampleType == .unsignedInteger, d.planes.count == 1, (2...16).contains(d.meaningfulBits) else {
        throw CodecError(.incompatibleImageLayout, "Netpbm output requires a single-plane 2..16-bit unsigned integer image.")
    }
    let isGrey = (d.colour == .greyscale && d.components == [.grey])
    let isRGB = (d.colour == .rgb && d.components == [.red, .green, .blue])
    guard isGrey || isRGB else {
        throw CodecError(.incompatibleImageLayout, "Netpbm output supports 1-component greyscale or 3-component RGB images only.")
    }
    if format == .pgm && !isGrey {
        throw CodecError(.incompatibleImageLayout, "PGM output requires a 1-component greyscale image.")
    }
    if format == .ppm && !isRGB {
        throw CodecError(.incompatibleImageLayout, "PPM output requires a 3-component RGB image.")
    }
    guard d.iccProfile == nil, image.metadata.entries.isEmpty else {
        throw CodecError(.unsupportedFormat, "Netpbm output cannot preserve embedded ICC or Exif metadata.")
    }
    let magic = isGrey ? "P5" : "P6"
    let maxval = (1 << d.meaningfulBits) - 1
    let header = "\(magic)\n\(d.width) \(d.height)\n\(maxval)\n"
    let headerData = Data(header.utf8)
    let components = d.components.count
    let outBps = d.meaningfulBits <= 8 ? 1 : 2
    let srcBps = d.storageBits / 8
    let pixels = try cliCheckedMultiply(d.width, d.height, limitError: true)
    let samples = try cliCheckedMultiply(pixels, components, limitError: true)
    let payloadBytes = try cliCheckedMultiply(samples, outBps, limitError: true)
    let totalBytes = try cliCheckedAdd(headerData.count, payloadBytes, limitError: true)
    guard payloadBytes <= limits.maximumDecodedBytes, totalBytes <= limits.maximumMemoryBytes else {
        throw CodecError(.resourceLimitExceeded, "Serialised Netpbm output exceeds --max-memory.")
    }
    var output = Data()
    output.reserveCapacity(totalBytes)
    output.append(headerData)
    let plane = d.planes[0]
    try image.storage.withUnsafeBytes { raw in
        for y in 0..<d.height {
            try context.check()
            for x in 0..<d.width {
                let pixelOff = plane.offset + y * plane.rowBytes + x * plane.pixelStride
                for c in 0..<components {
                    let sOff = pixelOff + c * plane.sampleStride
                    let sample: UInt16
                    if srcBps == 1 {
                        sample = UInt16(raw[sOff])
                    } else if d.byteOrder == .littleEndian {
                        sample = UInt16(raw[sOff]) | (UInt16(raw[sOff + 1]) << 8)
                    } else {
                        sample = (UInt16(raw[sOff]) << 8) | UInt16(raw[sOff + 1])
                    }
                    if outBps == 1 {
                        output.append(UInt8(truncatingIfNeeded: sample))
                    } else {
                        output.append(UInt8(sample >> 8))
                        output.append(UInt8(truncatingIfNeeded: sample))
                    }
                }
            }
        }
    }
    try context.check()
    return output
}

// MARK: - Asynchronous Codec Bridge

private nonisolated func runAsync<T: Sendable>(
    context: CommandExecutionContext,
    _ operation: @escaping @Sendable () async throws -> T
) throws -> T {
    try context.check()
    let box = Mutex<Result<T, any Error>?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    let task = Task.detached {
        let outcome: Result<T, any Error>
        do {
            try context.check()
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
        box.withLock { $0 = outcome }
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now() + .milliseconds(5)) == .timedOut {
        if interrupted.load(ordering: .relaxed) {
            task.cancel()
        } else if (try? context.remainingSeconds()) == nil {
            task.cancel()
        }
    }
    if interrupted.load(ordering: .relaxed) {
        throw CancellationError()
    }
    try context.check()
    do {
        return try box.withLock { $0! }.get()
    } catch is CancellationError {
        if interrupted.load(ordering: .relaxed) {
            throw CancellationError()
        }
        throw CodecError(.resourceLimitExceeded, "CLI command deadline exceeded.")
    }
}

private func mapCodecErrorCategory(_ category: CodecError.Category) -> Int32 {
    switch category {
    case .invalidArgument: return 2
    case .malformedInput: return 3
    case .unsupportedFormat, .unsupportedFeature, .incompatibleImageLayout, .backendUnavailable: return 4
    case .resourceLimitExceeded: return 5
    case .storageUnavailable, .ioFailure: return 6
    case .internalFailure: return 7
    }
}

private func describeCodingProcess(_ process: JPEGCodingProcess) -> String {
    switch process {
    case .predictive: return "predictive"
    case .sequentialDCT: return "sequentialDCT"
    case .progressiveDCT: return "progressiveDCT"
    }
}

private func describeSubsampling(_ sampling: JPEGChromaSubsampling) -> String {
    switch sampling {
    case .greyscale: return "greyscale"
    case .yuv444: return "4:4:4"
    case .yuv422: return "4:2:2"
    case .yuv420: return "4:2:0"
    case .other: return "other"
    }
}

private func describeBackend(_ backend: Backend) -> String {
    switch backend {
    case .scalarCPU: return "scalarCPU"
    case .accelerated: return "accelerated"
    }
}

private func describeColour(_ colour: ColourInterpretation) -> String {
    switch colour {
    case .greyscale: return "greyscale"
    case .rgb: return "rgb"
    case .unknown: return "unknown"
    }
}

private func describeMode(_ mode: CompressionMode) -> String {
    switch mode {
    case .lossless: return "lossless"
    case .nearLossless(let bound): return "near-lossless(\(bound))"
    case .lossy: return "lossy"
    }
}

private func describeFidelity(_ fidelity: Fidelity) -> (name: String, maxError: Any) {
    switch fidelity {
    case .exactSamples: return ("exactSamples", 0)
    case .boundedError(let bound): return ("boundedError", bound)
    case .lossy: return ("lossy", NSNull())
    case .originalBitstream: return ("originalBitstream", 0)
    }
}

// MARK: - Command Execution

private func run() throws -> Int32 {
    let startInstant = ContinuousClock.now
    let start = ProcessInfo.processInfo.systemUptime
    let options: Options
    do { options = try parse(Array(CommandLine.arguments.dropFirst())) }
    catch let error as UsageError {
        try write("\(tool): \(error.message)\n", to: .standardError)
        return 2
    }
    if options.help || (options.command == nil && !options.version) {
        try write(help(options.command), to: .standardOutput); return 0
    }
    if options.version { try write("\(tool) \(version)\n", to: .standardOutput); return 0 }
    func diagnostic(_ level: Int, _ message: String) throws {
        if !options.quiet && options.verbosity >= level {
            try write("[\(level)] \(tool): \(message)\n", to: .standardError)
        }
    }

    guard let command = options.command else { return 0 }

    if command == "capabilities" {
        try diagnostic(1, "development version \(version)")
        try diagnostic(2, "reporting capabilities")
        // Qualified deliberately so SwiftJLI.Encoder / SwiftJLI.Decoder never collide with Swift.Encoder / Swift.Decoder.
        let encoder = SwiftJLI.Encoder.capabilities
        let decoder = SwiftJLI.Decoder.capabilities
        let formats = Array(Set(encoder.formats + decoder.formats)).sorted()
        if options.json {
            let payload: [String: Any] = ["tool": tool, "version": version, "minimumAppleOS": minimumAppleOS,
                "canEncode": encoder.canEncode, "canDecode": decoder.canDecode,
                "canInspect": decoder.canInspect, "formats": formats]
            try writeJSON(payload, to: .standardOutput)
        } else {
            try write("\(tool) \(version)\nencode: \(encoder.canEncode)\ndecode: \(decoder.canDecode)\ninspect: \(decoder.canInspect)\nformats: \(formats.isEmpty ? "none" : formats.joined(separator: ", "))\n", to: .standardOutput)
        }
        try diagnostic(3, "advertised formats: \(formats.count); capability values read from the library")
        try diagnostic(4, "elapsed seconds: \(ProcessInfo.processInfo.systemUptime - start)")
        try diagnostic(5, "arguments validated; capability report emitted; no codec payload opened")
        return 0
    }

    do {
        guard let inputPath = options.inputPath else {
            throw UsageError(message: "--input is required for \(command).")
        }
        if command == "inspect" || command == "validate" {
            guard options.outputPath == nil, options.outputFormat == nil, !options.overwrite else {
                throw UsageError(message: "--output, --output-format, and --overwrite are not valid with \(command).")
            }
            guard options.mode == nil, options.maxError == nil, options.predictor == nil,
                  options.restartInterval == nil, options.quality == nil,
                  options.subsampling == nil, options.progressive == nil else {
                throw UsageError(message: "Encoder options are not valid with \(command).")
            }
        } else if command == "decode" {
            guard options.mode == nil, options.maxError == nil, options.predictor == nil,
                  options.restartInterval == nil, options.quality == nil,
                  options.subsampling == nil, options.progressive == nil else {
                throw UsageError(message: "Encoder options are not valid with decode.")
            }
            guard options.outputPath != nil else {
                throw UsageError(message: "--output is required for decode.")
            }
        } else if command == "encode" {
            guard options.outputPath != nil else {
                throw UsageError(message: "--output is required for encode.")
            }
        }

        let baseLimits = try buildResourceLimits(options)
        let context = CommandExecutionContext(limits: baseLimits, started: startInstant)
        let executionPolicy = try buildExecutionPolicy(options.backend)
        let copyPolicy = try buildCopyPolicy(options.copyPolicy)
        let inputFormat = try resolveInputFormat(path: inputPath, explicit: options.inputFormat, command: command)
        let outputFormat: CanonicalFormat? = try options.outputPath.map {
            try resolveOutputFormat(path: $0, explicit: options.outputFormat, command: command)
        }

        if let outputPath = options.outputPath {
            try preflightOutputDestination(outputPath, overwrite: options.overwrite, context: context)
        }

        let progressCallback: @Sendable (ProgressUpdate) -> Void = { _ in
            if interrupted.load(ordering: .relaxed) || (try? context.remainingSeconds()) == nil {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }

        try diagnostic(1, "development version \(version); command \(command)")
        try diagnostic(2, "stage input admission and format resolution (\(inputFormat.rawValue))")

        switch command {
        case "inspect":
            let data = try readBoundedInput(from: inputPath, maximumBytes: baseLimits.maximumCompressedBytes, context: context)
            let inspectLimits = try context.scopedLimits()
            let decodeOptions = DecodeOptions(
                resourceLimits: inspectLimits, executionPolicy: executionPolicy,
                copyPolicy: copyPolicy, metadataPolicy: .preserve, progress: progressCallback
            )
            let decoder = try SwiftJLI.Decoder()
            let info = try runAsync(context: context) {
                try decoder.inspectJPEG(data, options: decodeOptions)
            }
            try context.check()
            let d = info.imageInfo.descriptor
            let pt = info.pointTransform ?? 0
            let isExactLossless = (info.codingProcess == .predictive && pt == 0)
            let fidelityName = info.codingProcess != .predictive ? "lossy" : (pt == 0 ? "exactSamples" : "boundedError")
            let maxErrorVal: Any = info.codingProcess == .predictive ? ((1 << pt) - 1) : NSNull()
            try diagnostic(3, "inspected JPEG \(d.width)x\(d.height) components=\(info.componentCount) bits=\(info.bitsPerComponent) process=\(describeCodingProcess(info.codingProcess))")
            if options.json {
                var payload: [String: Any] = [
                    "tool": tool,
                    "version": version,
                    "format": "jpeg",
                    "codingProcess": describeCodingProcess(info.codingProcess),
                    "fidelity": fidelityName,
                    "maximumAbsoluteError": maxErrorVal,
                    "width": info.width,
                    "height": info.height,
                    "componentCount": info.componentCount,
                    "bitsPerComponent": info.bitsPerComponent,
                    "storageBits": d.storageBits,
                    "meaningfulBits": d.meaningfulBits,
                    "colour": describeColour(d.colour),
                    "chromaSubsampling": describeSubsampling(info.chromaSubsampling),
                    "isLossless": isExactLossless,
                    "isProgressive": info.isProgressive,
                    "isXYB": info.isXYB,
                    "restartInterval": info.restartInterval,
                    "scanCount": info.scanCount,
                    "frameCount": info.imageInfo.frameCount,
                    "hasICCProfile": d.iccProfile != nil,
                    "hasExif": info.imageInfo.metadata.entries["Exif"] != nil
                ]
                payload["predictor"] = info.predictor ?? NSNull()
                payload["pointTransform"] = info.pointTransform ?? NSNull()
                try context.check()
                try writeJSON(payload, to: .standardOutput)
            } else {
                var lines = [
                    "format: jpeg",
                    "codingProcess: \(describeCodingProcess(info.codingProcess))",
                    "fidelity: \(fidelityName)",
                    "width: \(info.width)",
                    "height: \(info.height)",
                    "components: \(info.componentCount)",
                    "colour: \(describeColour(d.colour))",
                    "bitsPerComponent: \(info.bitsPerComponent)",
                    "storageBits: \(d.storageBits)",
                    "chromaSubsampling: \(describeSubsampling(info.chromaSubsampling))",
                    "lossless: \(isExactLossless)",
                    "progressive: \(info.isProgressive)",
                    "restartInterval: \(info.restartInterval)",
                    "scanCount: \(info.scanCount)"
                ]
                if let predictor = info.predictor { lines.append("predictor: \(predictor)") }
                if let pointTransform = info.pointTransform {
                    lines.append("pointTransform: \(pointTransform)")
                    lines.append("maximumAbsoluteError: \((1 << pointTransform) - 1)")
                }
                try context.check()
                try write(lines.joined(separator: "\n") + "\n", to: .standardOutput)
            }
            try diagnostic(4, "elapsed seconds: \(ProcessInfo.processInfo.systemUptime - start)")
            try diagnostic(5, "header inspection completed; no entropy decode or file write performed")
            return 0

        case "validate":
            let data = try readBoundedInput(from: inputPath, maximumBytes: baseLimits.maximumCompressedBytes, context: context)
            let validateLimits = try context.scopedLimits()
            let decodeOptions = DecodeOptions(
                resourceLimits: validateLimits, executionPolicy: executionPolicy,
                copyPolicy: copyPolicy, metadataPolicy: .preserve, progress: progressCallback
            )
            let decoder = try SwiftJLI.Decoder()
            let info = try runAsync(context: context) {
                try decoder.inspectJPEG(data, options: decodeOptions)
            }
            let decoded = try runAsync(context: context) {
                try await decoder.decode(data, options: decodeOptions)
            }
            try context.check()
            let d = decoded.image.descriptor
            let fid = describeFidelity(decoded.report.fidelity)
            try diagnostic(3, "validated JPEG \(d.width)x\(d.height) components=\(d.components.count) bits=\(d.meaningfulBits) backend=\(describeBackend(decoded.report.backend))")
            if options.json {
                let payload: [String: Any] = [
                    "tool": tool,
                    "version": version,
                    "valid": true,
                    "format": "jpeg",
                    "codingProcess": describeCodingProcess(info.codingProcess),
                    "fidelity": fid.name,
                    "maximumAbsoluteError": fid.maxError,
                    "width": d.width,
                    "height": d.height,
                    "componentCount": d.components.count,
                    "bitsPerComponent": d.meaningfulBits,
                    "storageBits": d.storageBits,
                    "meaningfulBits": d.meaningfulBits,
                    "colour": describeColour(d.colour),
                    "backend": describeBackend(decoded.report.backend),
                    "fallbackReason": decoded.report.fallbackReason ?? NSNull(),
                    "copyEventCount": decoded.report.copyEvents.count,
                    "pixelAllocationCount": decoded.report.pixelAllocationCount ?? NSNull(),
                    "peakPixelBytes": decoded.report.peakPixelBytes ?? NSNull(),
                    "peakWorkspaceBytes": decoded.report.peakWorkspaceBytes ?? NSNull()
                ]
                try context.check()
                try writeJSON(payload, to: .standardOutput)
            } else {
                let text = """
                valid: true
                format: jpeg
                codingProcess: \(describeCodingProcess(info.codingProcess))
                fidelity: \(fid.name)
                width: \(d.width)
                height: \(d.height)
                components: \(d.components.count)
                bitsPerComponent: \(d.meaningfulBits)
                backend: \(describeBackend(decoded.report.backend))
                pixelAllocationCount: \(decoded.report.pixelAllocationCount.map(String.init) ?? "unknown")
                peakPixelBytes: \(decoded.report.peakPixelBytes.map(String.init) ?? "unknown")
                """
                try context.check()
                try write(text + "\n", to: .standardOutput)
            }
            try diagnostic(4, "elapsed seconds: \(ProcessInfo.processInfo.systemUptime - start)")
            try diagnostic(5, "full stream and entropy validation completed; copyEvents=\(decoded.report.copyEvents.count)")
            return 0

        case "decode":
            guard let outputPath = options.outputPath, let targetFormat = outputFormat else {
                throw UsageError(message: "--output is required for decode.")
            }
            var data = try readBoundedInput(from: inputPath, maximumBytes: baseLimits.maximumCompressedBytes, context: context)
            let decodeLimits = try context.scopedLimits()
            let decodeOptions = DecodeOptions(
                resourceLimits: decodeLimits, executionPolicy: executionPolicy,
                copyPolicy: copyPolicy, metadataPolicy: .preserve, progress: progressCallback
            )
            let decoder = try SwiftJLI.Decoder()
            let info: JPEGInspection
            let decoded: DecodedImage
            do {
                let inputCopy = data
                info = try runAsync(context: context) {
                    try decoder.inspectJPEG(inputCopy, options: decodeOptions)
                }
                decoded = try runAsync(context: context) {
                    try await decoder.decode(inputCopy, options: decodeOptions)
                }
            }
            // Release compressed input buffer before allocating serialised uncompressed output.
            data = Data()
            let d = decoded.image.descriptor
            let report = decoded.report
            let retainedImageBytes = decoded.image.storage.byteCount
            let outBytes: Data
            switch targetFormat {
            case .nrrd:
                outBytes = try writeNRRD(decoded.image, reservedBytes: retainedImageBytes, context: context)
            case .pgm, .ppm, .pnm:
                outBytes = try writeNetpbm(decoded.image, format: targetFormat, reservedBytes: retainedImageBytes, context: context)
            case .jpeg:
                throw CodecError(.unsupportedFormat, "decode requires an uncompressed output format.")
            }
            try writeOutputAtomically(outBytes, to: outputPath, overwrite: options.overwrite, context: context)
            let fid = describeFidelity(report.fidelity)
            try diagnostic(3, "decoded \(d.width)x\(d.height) bits=\(d.meaningfulBits) to \(targetFormat.rawValue) (\(outBytes.count) bytes) backend=\(describeBackend(report.backend))")
            try diagnostic(4, "elapsed seconds: \(ProcessInfo.processInfo.systemUptime - start)")
            try diagnostic(5, "decode committed atomically; copyEvents=\(report.copyEvents.count)")
            if options.json {
                let jsonReport: [String: Any] = [
                    "tool": tool,
                    "version": version,
                    "command": "decode",
                    "inputFormat": "jpeg",
                    "outputFormat": targetFormat.rawValue,
                    "codingProcess": describeCodingProcess(info.codingProcess),
                    "fidelity": fid.name,
                    "maximumAbsoluteError": fid.maxError,
                    "width": d.width,
                    "height": d.height,
                    "componentCount": d.components.count,
                    "meaningfulBits": d.meaningfulBits,
                    "storageBits": d.storageBits,
                    "backend": describeBackend(report.backend),
                    "fallbackReason": report.fallbackReason ?? NSNull(),
                    "outputBytes": outBytes.count,
                    "copyEventCount": report.copyEvents.count,
                    "pixelAllocationCount": report.pixelAllocationCount ?? NSNull(),
                    "peakPixelBytes": report.peakPixelBytes ?? NSNull(),
                    "peakWorkspaceBytes": report.peakWorkspaceBytes ?? NSNull()
                ]
                try writeJSON(jsonReport, to: .standardError)
            }
            return 0

        case "encode":
            guard let outputPath = options.outputPath, let targetFormat = outputFormat, targetFormat == .jpeg else {
                throw UsageError(message: "--output is required for encode.")
            }
            let encoderConfig = try buildEncoderConfiguration(options)
            let encoder = try SwiftJLI.Encoder(configuration: encoderConfig)
            let headerAllowance = 64 * 1024
            let maxInput = min(
                baseLimits.maximumMemoryBytes,
                baseLimits.maximumDecodedBytes.addingReportingOverflow(headerAllowance).partialValue
            )
            var rawInput = try readBoundedInput(from: inputPath, maximumBytes: maxInput, context: context)
            let retainedInputBytes = rawInput.count
            let sourceImage: Image
            switch inputFormat {
            case .nrrd:
                sourceImage = try readNRRD(rawInput, reservedBytes: retainedInputBytes, context: context)
            case .pgm, .ppm, .pnm:
                sourceImage = try readNetpbm(rawInput, declaredFormat: inputFormat, reservedBytes: retainedInputBytes, context: context)
            case .jpeg:
                throw CodecError(.unsupportedFormat, "encode requires an uncompressed input format.")
            }
            // Release raw file input buffer before running codec workspace + output allocation.
            rawInput = Data()
            let encodeLimits = try context.scopedLimits()
            let encodeOptions = EncodeOptions(
                resourceLimits: encodeLimits, executionPolicy: executionPolicy,
                copyPolicy: copyPolicy, metadataPolicy: .preserve, progress: progressCallback
            )
            let encoded = try runAsync(context: context) {
                try await encoder.encode(sourceImage, options: encodeOptions)
            }
            let d = sourceImage.descriptor
            let report = encoded.report
            let fid = describeFidelity(report.fidelity)
            try writeOutputAtomically(encoded.data, to: outputPath, overwrite: options.overwrite, context: context)
            try diagnostic(3, "encoded \(d.width)x\(d.height) bits=\(d.meaningfulBits) mode=\(describeMode(encoded.encoding.mode)) (\(encoded.data.count) bytes) backend=\(describeBackend(report.backend))")
            try diagnostic(4, "elapsed seconds: \(ProcessInfo.processInfo.systemUptime - start)")
            try diagnostic(5, "encode committed atomically; copyEvents=\(report.copyEvents.count)")
            if options.json {
                let jsonReport: [String: Any] = [
                    "tool": tool,
                    "version": version,
                    "command": "encode",
                    "inputFormat": inputFormat.rawValue,
                    "outputFormat": "jpeg",
                    "mode": describeMode(encoded.encoding.mode),
                    "fidelity": fid.name,
                    "maximumAbsoluteError": fid.maxError,
                    "width": d.width,
                    "height": d.height,
                    "componentCount": d.components.count,
                    "meaningfulBits": d.meaningfulBits,
                    "storageBits": d.storageBits,
                    "backend": describeBackend(report.backend),
                    "fallbackReason": report.fallbackReason ?? NSNull(),
                    "encodedBytes": encoded.data.count,
                    "copyEventCount": report.copyEvents.count,
                    "pixelAllocationCount": report.pixelAllocationCount ?? NSNull(),
                    "peakPixelBytes": report.peakPixelBytes ?? NSNull(),
                    "peakWorkspaceBytes": report.peakWorkspaceBytes ?? NSNull()
                ]
                try writeJSON(jsonReport, to: .standardError)
            }
            return 0

        default:
            throw UsageError(message: "Unknown command. Use \(tool) --help.")
        }
    } catch is CancellationError {
        try? write("\(tool): operation cancelled.\n", to: .standardError)
        return 130
    } catch let error as UsageError {
        try write("\(tool): \(error.message)\n", to: .standardError)
        return 2
    } catch let error as FileIOError {
        try write("\(tool): \(error.message)\n", to: .standardError)
        return 6
    } catch let error as CodecError {
        let code = mapCodecErrorCategory(error.category)
        try write("\(tool): \(error.category.rawValue): \(error.message)\n", to: .standardError)
        return code
    }
}

installSignalHandlers()
do { exit(try run()) }
catch {
    try? write("\(tool): output I/O failure.\n", to: .standardError)
    exit(6)
}
