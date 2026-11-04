// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
enum QualifiedMarker {
    // Start/End
    static let soi: UInt8 = 0xD8   // Start of Image
    static let eoi: UInt8 = 0xD9   // End of Image

    // Frame types
    static let sof0: UInt8 = 0xC0  // Baseline DCT (8-bit only)
    static let sof1: UInt8 = 0xC1  // Extended sequential DCT (8 or 12-bit)
    static let sof2: UInt8 = 0xC2  // Progressive DCT
    static let sof3: UInt8 = 0xC3  // Lossless (sequential, predictive)

    // Huffman tables
    static let dht: UInt8 = 0xC4   // Define Huffman Table

    // QualifiedQuantization tables
    static let dqt: UInt8 = 0xDB   // Define QualifiedQuantization Table

    // Scan
    static let sos: UInt8 = 0xDA   // Start of Scan

    // Application segments
    static let app0: UInt8 = 0xE0  // JFIF
    static let app1: UInt8 = 0xE1  // Exif
    static let app2: UInt8 = 0xE2  // ICC Profile

    // Restart
    static let dri: UInt8 = 0xDD   // Define Restart Interval
    static let rst0: UInt8 = 0xD0  // Restart marker 0

    // Comment
    static let com: UInt8 = 0xFE   // Comment

    /// Prefix byte for all JPEG markers.
    static let prefix: UInt8 = 0xFF
}
