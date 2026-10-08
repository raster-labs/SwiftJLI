// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftJLI
import Darwin

/// Public-API failure/concurrency experiment. Only allocator scopes are global;
/// each batch is awaited completely before the next scope begins.
@MainActor func runMemoryStress(controlCopy: Bool) async throws {
    try require(try calibrate(), "Apple allocation statistics calibration failed")
    let useRGB = CommandLine.arguments.contains("--rgb8")
    for size in [257, 1024] {
        let descriptor = try ImageDescriptor.greyscale16(width: size, height: size, meaningfulBits: 12)
        let source: Image
        if useRGB {
            let plane = try PlaneDescriptor(width: size, height: size, components: [0, 1, 2],
                sampleStride: 1, pixelStride: 3, rowBytes: size * 3, byteCount: size * size * 3)
            let rgb = try ImageDescriptor(width: size, height: size, storageBits: 8, meaningfulBits: 8,
                components: [.red, .green, .blue], colour: .rgb, planes: [plane])
            source = try ImageDestination.allocate(descriptor: rgb).write { raw in
                for i in raw.indices { raw[i] = UInt8(truncatingIfNeeded: i * 17 + (i / (size * 3)) * 31) }
            }
        } else {
            source = try ImageDestination.allocate(descriptor: descriptor).writeUInt16 { x, y in
                UInt16((x * 17 + y * 31) & 4095)
            }
        }
        // Fails at the final logical sample, after constructing algorithm planes.
        let invalid = try ImageDestination.allocate(descriptor: descriptor).write { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            raw[raw.count - 1] = 0x10
        }
        let encoder = try Encoder(configuration: .init(mode: .lossy))
        let limits = try ResourceLimits(maximumWorkspaceBytes: 1024 * 1024 * 1024, maximumWorkers: 2, maximumMemoryBytes: 2 * 1024 * 1024 * 1024)
        let jpeg = try await encoder.encode(source, options: .init(resourceLimits: limits))
        let decoder = try Decoder()
        let reference = try await decoder.decode(jpeg.data, options: .init(resourceLimits: limits))
        let denied = try ResourceLimits(maximumWorkspaceBytes: 1, maximumWorkers: 2)
        let modes = ["concurrentEncode", "concurrentDecode", "invalidFinalSample",
                     "encodeAdmissionDenied", "decodeAdmissionDenied", "encodeCancellation", "decodeCancellation"]
        for mode in modes {
            @Sendable func one() async throws {
                // Isolate cancellation so it cannot poison the measurement parent.
                try await Task {
                    let cancel: @Sendable (ProgressUpdate) -> Void = { update in
                        if update.phase == .processing { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                    do {
                        switch mode {
                        case "concurrentEncode":
                            let result = try await encoder.encode(source, options: .init(resourceLimits: limits))
                            try require(result.data == jpeg.data, "Concurrent encode changed codestream")
                        case "concurrentDecode":
                            let result = try await decoder.decode(jpeg.data, options: .init(resourceLimits: limits))
                            try equalSamples(reference.image, result.image)
                        case "invalidFinalSample": _ = try await encoder.encode(invalid, options: .init(resourceLimits: limits))
                        case "encodeAdmissionDenied": _ = try await encoder.encode(source, options: .init(resourceLimits: denied))
                        case "decodeAdmissionDenied": _ = try await decoder.decode(jpeg.data, options: .init(resourceLimits: denied))
                        case "encodeCancellation": _ = try await encoder.encode(source, options: .init(resourceLimits: limits, progress: cancel))
                        default: _ = try await decoder.decode(jpeg.data, options: .init(resourceLimits: limits, progress: cancel))
                        }
                        try require(mode.hasPrefix("concurrent"), "Failure/cancellation incorrectly published success")
                    } catch is CancellationError {
                        try require(mode.hasSuffix("Cancellation"), "Unexpected cancellation")
                    } catch let error as CodecError {
                        if mode == "invalidFinalSample" { try require(error.category == .invalidArgument, "Wrong invalid-sample error") }
                        else if mode.hasSuffix("AdmissionDenied") { try require(error.category == .resourceLimitExceeded, "Wrong admission error") }
                        else { throw error }
                    }
                }.value
            }
            for _ in 0..<5 { try await one() }
            for operations in [2, 32] {
                beginMeasuredScope()
                var retained: [[UInt8]] = []
                do {
                    // At most two in-flight operations, each capped at two workers.
                    for _ in 0..<(operations / 2) {
                        async let a: Void = one()
                        async let b: Void = one()
                        _ = try await (a, b)
                        if controlCopy {
                            retained.append(try source.storage.withUnsafeBytes { Array($0) })
                            retained.append(try source.storage.withUnsafeBytes { Array($0) })
                        }
                    }
                } catch { _ = endMeasuredScope(); throw error }
                let stats = withExtendedLifetime(retained) { endMeasuredScope() }
                let measurement = try snapshot(stats)
                if controlCopy {
                    try require(stats.liveIncrease >= (source.storage.byteCount * operations), "Retained-frame control missed")
                } else {
                    // This detects a retained full source frame, not arbitrary tiny leaks.
                    try require(stats.liveIncrease < (source.storage.byteCount), "A full frame remains live after joined batch")
                }
                try emit(["event": "stress", "mode": mode, "width": size, "height": size,
                    "operations": operations, "maximumInFlight": 2, "workersPerOperation": 2,
                    "profile": useRGB ? "rgb8" : "dct12", "maximumWorkspaceBytes": limits.maximumWorkspaceBytes, "maximumMemoryBytes": limits.maximumMemoryBytes, "sourceBytes": source.storage.byteCount, "controlCopy": controlCopy,
                    "expectedOutcomes": true, "measurement": measurement])
            }
        }
    }
}
