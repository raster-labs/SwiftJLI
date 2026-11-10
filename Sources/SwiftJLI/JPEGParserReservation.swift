// SPDX-License-Identifier: MIT

/// Conservative parser admission, not measured allocator or RSS telemetry.
/// Entropy ranges retain the compressed owner without expanding its payload.
/// Definitions are counted even when a later definition replaces the same ID.
enum JPEGParserReservation {
    static let fixedReserve = 1_048_576

    /// Must pass before constructing an immutable Foundation input owner.
    /// Data may require one bridge copy; the array convenience first makes Data.
    static func bootstrap(compressedBytes: Int, inputCopies: Int = 1) throws -> Int {
        guard compressedBytes >= 0, inputCopies == 1 || inputCopies == 2 else {
            throw CodecError(.resourceLimitExceeded, "Invalid JPEG parser reservation.")
        }
        return try checkedAdd(checkedMultiply(compressedBytes, inputCopies), fixedReserve)
    }

    /// The fixed reserve retains the existing allocator/backend allowance.
    /// A decoder-only Huffman table has at most 1,056 bytes of logical array
    /// payload; 4 KiB also covers headers, growth and DHT tuples. A quantiser
    /// has 512 bytes of Int payload plus its tuple/growth allowance. Each scan
    /// retains two at-most-four-key dictionary snapshots and small records.
    /// Frame/scan components occupy 32/24 bytes on supported 64-bit ABIs.
    /// Four times APP payload covers segment/chunk/assembly and later Data
    /// metadata copies. These allowances deliberately overcount released tables
    /// and skipped APP0 data. No resource ceiling is inferred from these counts.
    static func workspace(compressedBytes: Int, huffmanDefinitions: Int,
                          quantisationDefinitions: Int, scans: Int,
                          frameComponents: Int, scanComponents: Int,
                          metadataBytes: Int, inputCopies: Int = 1) throws -> Int {
        guard huffmanDefinitions >= 0, quantisationDefinitions >= 0, scans >= 0,
              frameComponents >= 0, scanComponents >= 0, metadataBytes >= 0 else {
            throw CodecError(.resourceLimitExceeded, "Invalid JPEG parser reservation.")
        }
        // Keep the array convenience's second input-copy allowance through
        // parsing rather than depending on temporary Foundation release timing.
        var bytes = try bootstrap(compressedBytes: compressedBytes, inputCopies: inputCopies)
        bytes = try checkedAdd(bytes, checkedMultiply(huffmanDefinitions, 4096))
        bytes = try checkedAdd(bytes, checkedMultiply(quantisationDefinitions, 1024))
        bytes = try checkedAdd(bytes, checkedMultiply(scans, 4096))
        bytes = try checkedAdd(bytes, checkedMultiply(checkedAdd(frameComponents, scanComponents), 64))
        return try checkedAdd(bytes, checkedMultiply(metadataBytes, 4))
    }
}
