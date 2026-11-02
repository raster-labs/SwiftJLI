// SPDX-License-Identifier: Apache-2.0
import Foundation

// Blocking package-only host adapters for the command-line executable. They use
// the same validated kernels and owning-storage lifecycle as the public async
// API. CPU work runs on the calling thread and synchronously joined workers;
// the executable supplies its signal/deadline check at every cancellation point.
// Application clients retain the public @concurrent async execution policy.
extension Decoder {
    package func decodeSynchronously(
        _ data: Data, into destination: ImageDestination? = nil,
        options: DecodeOptions = .init(),
        cancellationCheck: @escaping @Sendable () throws -> Void
    ) throws -> DecodedImage {
        try NativeOperation.withSynchronousCancellation(cancellationCheck) {
            try JPEGCodec.decode(data, into: destination, configuration: configuration, options: options)
        }
    }

    package func inspectJPEGSynchronously(
        _ data: Data, options: DecodeOptions = .init(),
        cancellationCheck: @escaping @Sendable () throws -> Void
    ) throws -> JPEGInspection {
        try NativeOperation.withSynchronousCancellation(cancellationCheck) {
            try inspectJPEG(data, options: options)
        }
    }
}

extension Encoder {
    package func encodeSynchronously(
        _ image: Image, options: EncodeOptions = .init(),
        cancellationCheck: @escaping @Sendable () throws -> Void
    ) throws -> EncodedImage {
        try NativeOperation.withSynchronousCancellation(cancellationCheck) {
            try JPEGCodec.encode(image, configuration: configuration, options: options)
        }
    }
}
