// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct Seed {
    let data: Data
    let configuration: DecoderConfiguration
    let descriptor: ImageDescriptor
}
struct Generator {
    var state: UInt64 = 0x53574946544A4C49
    mutating func number(_ upper: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(upper))
    }
    mutating func mutate(_ original: Data) -> Data {
        var bytes = Array(original)
        switch number(8) {
        case 0: break // Valid seeds continually reach final sample reconstruction.
        case 1: bytes.removeSubrange(number(bytes.count + 1)..<bytes.count)
        case 2: for _ in 0..<number(12) + 1 { bytes[number(bytes.count)] ^= UInt8(1 << number(8)) }
        case 3: for _ in 0..<number(12) + 1 { bytes[number(bytes.count)] = UInt8(number(256)) }
        case 4:
            let offset = number(bytes.count)
            bytes.insert(contentsOf: [UInt8](repeating: UInt8(number(256)), count: number(128) + 1), at: offset)
        case 5:
            let offset = number(bytes.count), count = min(number(128) + 1, bytes.count - offset)
            bytes.removeSubrange(offset..<(offset + count))
        case 6:
            let markers = bytes.indices.dropLast().filter { bytes[$0] == 255 && bytes[$0 + 1] != 0 }
            if let offset = markers.isEmpty ? nil : markers[number(markers.count)], offset + 3 < bytes.count {
                bytes[offset + 2] = UInt8(number(256)); bytes[offset + 3] = UInt8(number(256))
            }
        default:
            let offset = number(bytes.count)
            for i in offset..<min(offset + number(256) + 1, bytes.count) { bytes[i] = UInt8(number(256)) }
        }
        return Data(bytes)
    }
}

@main struct Fuzz {
    static func emit(_ payload: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        data.append(10); try FileHandle.standardOutput.write(contentsOf: data)
    }
    static func peakRSS() -> Int64 {
        var usage = rusage()
        #if os(Linux)
        guard getrusage(RUSAGE_SELF.rawValue, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss) * 1024
        #else
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss)
        #endif
    }
    static func seeds() async throws -> [Seed] {
        var result: [Seed] = []
        for (bits, components) in [(8, 1), (8, 3), (12, 1), (12, 3), (16, 1)] {
            let w = 19, h = 13, bps = bits == 8 ? 1 : 2
            let p = try PlaneDescriptor(width: w, height: h, components: Array(0..<components),
                sampleStride: bps, pixelStride: components * bps, rowBytes: w * components * bps,
                byteCount: w * h * components * bps)
            let d = try ImageDescriptor(width: w, height: h, storageBits: bps * 8, meaningfulBits: bits,
                components: components == 1 ? [.grey] : [.red, .green, .blue], colour: components == 1 ? .greyscale : .rgb, planes: [p])
            let image = try ImageDestination.allocate(descriptor: d).write { raw in
                for i in 0..<(w * h * components) {
                    let value = (i * 197 + i / w * 53) & ((1 << bits) - 1)
                    for byte in 0..<bps { raw[i * bps + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
                }
            }
            var configs = [try EncoderConfiguration(), try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: 3))]
            if bits <= 12 {
                for script: ProgressiveMode in [.sequential, .spectralSelection, .successiveApproximation] {
                    configs.append(try .init(mode: .lossy, codecOptions: .init(dct: .init(progressiveMode: script))))
                }
            }
            if bits == 8 && components == 3 {
                configs.append(try .init(mode: .lossy, codecOptions: .init(dct: .init(chromaSubsampling: .yuv444, colourSpace: .xybFromSRGB))))
            }
            for config in configs {
                let jpeg = try await Encoder(configuration: config).encode(image, options: .init(executionPolicy: .scalarCPU))
                var formats: [DecoderSampleFormat] = [.nativeInteger]
                if config.mode == .lossy && components == 1 { formats.append(.float32RawSamples) }
                if config.codecOptions.dct.colourSpace == .xybFromSRGB { formats.append(.float32NormalisedSRGB) }
                for format in formats { for scale in config.mode == .lossy ? [1, 2, 4, 8] : [1] {
                    let dc = DecoderConfiguration(scale: scale, sampleFormat: format)
                    let output = try await Decoder(configuration: dc).decode(jpeg.data, options: .init(executionPolicy: .scalarCPU))
                    result.append(.init(data: jpeg.data, configuration: dc, descriptor: output.image.descriptor))
                } }
            }
        }
        return result
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard (args.count == 4 || args.count == 5), ["inspect", "allocate", "destination"].contains(args[1]),
              let seconds = Double(args[2]), seconds.isFinite, seconds > 0, seconds <= 86400 else {
            throw CodecError(.invalidArgument, "Usage: DecoderFuzz inspect|allocate|destination seconds failure-file [replay-attempt]")
        }
        let replay = args.count == 5 ? Int(args[4]) : nil
        guard args.count == 4 || (replay.map { $0 > 0 } ?? false) else {
            throw CodecError(.invalidArgument, "Replay attempt must be positive.")
        }
        let entry = args[1], corpus = try await seeds()
        let limits = try ResourceLimits(maximumCompressedBytes: 1 << 20, maximumDecodedBytes: 1 << 20,
            maximumWorkspaceBytes: 32 << 20, maximumPixels: 4096, maximumDimension: 128,
            maximumMetadataBytes: 16384, maximumICCBytes: 8192, maximumWorkers: 1,
            deadlineSeconds: 0.2, maximumMemoryBytes: 64 << 20)
        let options = DecodeOptions(resourceLimits: limits, executionPolicy: .scalarCPU)
        let started = ContinuousClock.now
        var lastReport = started, rng = Generator(), attempts = 0, accepted = 0, rejected = 0
        var categories: [String: Int] = [:]
        try emit(["event": "start", "entry": entry, "seconds": seconds, "seeds": corpus.count,
                  "generator_seed": String(rng.state), "peak_rss_bytes": peakRSS()])
        while replay.map({ attempts < $0 }) ?? (started.duration(to: .now) < .seconds(seconds)) {
            let seed = corpus[rng.number(corpus.count)], data = rng.mutate(seed.data)
            attempts += 1
            if attempts == replay { try data.write(to: URL(fileURLWithPath: args[3])) }
            do {
                let decoder = try Decoder(configuration: seed.configuration)
                if entry == "inspect" { _ = try decoder.inspect(data, options: options) }
                else if entry == "allocate" { _ = try await decoder.decode(data, options: options) }
                else {
                    let destination = try ImageDestination.allocate(descriptor: seed.descriptor, limits: limits)
                    _ = try await decoder.decode(data, into: destination, options: options)
                }
                accepted += 1
            } catch let error as CodecError where error.category != .internalFailure {
                rejected += 1; categories[String(describing: error.category), default: 0] += 1
            } catch {
                try data.write(to: URL(fileURLWithPath: args[3]))
                try emit(["event": "failure", "entry": entry, "attempt": attempts, "error": String(describing: error)])
                throw error
            }
            if lastReport.duration(to: .now) >= .seconds(1) {
                lastReport = .now
                try emit(["event": "progress", "entry": entry, "attempts": attempts,
                          "accepted": accepted, "rejected": rejected, "peak_rss_bytes": peakRSS()])
            }
        }
        let elapsed = started.duration(to: .now).components
        try emit(["event": "complete", "entry": entry, "attempts": attempts, "accepted": accepted,
            "rejected": rejected, "errors": categories, "peak_rss_bytes": peakRSS(),
            "elapsed_seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18])
    }
}
