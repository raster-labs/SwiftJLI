// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.

/// Metadata about a decoded JPEG, exposing any advanced features detected in the bitstream.
struct JLIJPEGInfo: Sendable {
    /// The image width in pixels.
    let width: Int

    /// The image height in pixels.
    let height: Int

    /// The number of color components.
    let componentCount: Int

    /// The bits per component as stored in the JPEG (8 for standard, >8 for jpegli extended).
    let bitsPerComponent: Int

    /// Whether the JPEG uses progressive encoding.
    let isProgressive: Bool

    /// Whether the JPEG was encoded with XYB color space (detected via ICC profile).
    let isXYB: Bool

    /// Whether the JPEG uses jpegli's extended precision (10+ bit).
    let isExtendedPrecision: Bool

    /// The chroma subsampling mode detected in the JPEG.
    let chromaSubsampling: JLIChromaSubsampling
}
