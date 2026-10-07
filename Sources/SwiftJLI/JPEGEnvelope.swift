// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Allocation-free structural admission before the predecessor table parser.
/// Each segment must fit its own declared extent; bytes in the next segment
/// cannot satisfy a truncated SOF/SOS/table. Entropy is scanned, never decoded.
enum JPEGEnvelope {
    @discardableResult static func validate(_ b: [UInt8], limits: ResourceLimits) throws -> UInt8? {
        func malformed() -> CodecError { .init(.malformedInput, "Invalid JPEG marker envelope.") }
        guard b.count >= 4, b[0] == 255, b[1] == 216 else { throw malformed() }
        var p = 2, sawFrame = false, sawScan = false, metadata = 0, iccBytes = 0
        var frameMarker: UInt8 = 0, scanCount = 0
        var adobeTransform: UInt8?
        var iccCount: Int?, iccSequences = Set<Int>(), sawExif = false
        let iccID = Array("ICC_PROFILE\0".utf8), exifID: [UInt8] = [69,120,105,102,0,0]
        while p < b.count {
            try NativeOperation.check()
            guard b[p] == 255 else { throw malformed() }
            while p < b.count && b[p] == 255 {
                if p % 4096 == 0 { try NativeOperation.check() }
                p += 1
            }
            guard p < b.count else { throw malformed() }
            let marker = b[p]; p += 1
            if marker == 217 {
                guard sawFrame, sawScan, p == b.count,
                      iccCount == nil || iccSequences.count == iccCount else { throw malformed() }
                if let adobeTransform, (frameMarker == 0xC3 ? adobeTransform != 0 : adobeTransform > 1) {
                    throw CodecError(.unsupportedFeature, "JPEG colour transform is unsupported for this frame.")
                }
                return adobeTransform
            }
            guard marker != 0, marker != 216, !(208...215).contains(marker), p + 2 <= b.count else { throw malformed() }
            let length = Int(b[p]) * 256 + Int(b[p + 1])
            guard length >= 2, length <= b.count - p else { throw malformed() }
            let end = p + length, start = p + 2
            switch marker {
            case 0xC0, 0xC1, 0xC2, 0xC3:
                guard !sawFrame, length >= 8 else { throw malformed() }
                guard marker != 0xC0 || b[start] == 8 else { throw malformed() }
                let nc = Int(b[start + 5])
                guard nc > 0, length == 8 + nc * 3 else { throw malformed() }
                let height = Int(b[start + 1]) * 256 + Int(b[start + 2])
                let width = Int(b[start + 3]) * 256 + Int(b[start + 4])
                guard width > 0, height > 0 else { throw malformed() }
                guard width <= limits.maximumDimension, height <= limits.maximumDimension,
                      try checkedMultiply(width, height) <= limits.maximumPixels else {
                    throw CodecError(.resourceLimitExceeded, "JPEG dimensions exceed operation limits.")
                }
                var ids = Set<UInt8>()
                for c in 0..<nc {
                    guard ids.insert(b[start + 6 + c * 3]).inserted else { throw malformed() }
                }
                sawFrame = true; frameMarker = marker
            case 0xDA:
                scanCount += 1
                guard scanCount <= 128 else { throw CodecError(.resourceLimitExceeded, "JPEG scan limit exceeded.") }
                guard !sawScan || frameMarker == 0xC2 else {
                    throw CodecError(.unsupportedFeature, "Multiple sequential scans are unsupported.")
                }
                guard sawFrame, length >= 6 else { throw malformed() }
                let nc = Int(b[start])
                guard nc > 0, length == 6 + nc * 2 else { throw malformed() }
                sawScan = true
            case 0xDD:
                guard !sawScan else { throw CodecError(.unsupportedFeature, "Changing restart intervals between scans is unsupported.") }
                guard length == 4 else { throw malformed() }
            case 0xDB:
                guard !sawScan else { throw CodecError(.unsupportedFeature, "Changing quantisation tables between scans is unsupported.") }
                var q = start
                while q < end {
                    let precision = b[q] >> 4
                    guard precision <= 1, b[q] & 15 <= 3 else { throw malformed() }
                    q += 1 + (precision == 0 ? 64 : 128)
                }
                guard q == end else { throw malformed() }
            case 0xC4:
                var tableIDs = Set<UInt8>()
                var q = start
                while q < end {
                    guard end - q >= 17, b[q] >> 4 <= 1, b[q] & 15 <= 3 else { throw malformed() }
                    guard tableIDs.insert(b[q]).inserted else {
                        throw CodecError(.unsupportedFeature, "Repeated table definitions in one DHT segment are unsupported.")
                    }
                    var symbols = 0, slots = 1
                    for i in 1...16 {
                        slots = slots * 2 - Int(b[q + i])
                        guard slots >= 0 else { throw malformed() }
                        symbols += Int(b[q + i])
                    }
                    guard symbols > 0, symbols <= 256, symbols <= end - q - 17 else { throw malformed() }
                    q += 17 + symbols
                }
            case 0xE0...0xEF, 0xFE:
                metadata = try checkedAdd(metadata, length - 2)
                guard metadata <= limits.maximumMetadataBytes else {
                    throw CodecError(.resourceLimitExceeded, "JPEG metadata limit exceeded.")
                }
                if marker == 0xE1 {
                    guard end - start >= 6, b[start..<(start + 6)].elementsEqual(exifID) else {
                        throw CodecError(.unsupportedFeature, "Unsupported APP1 metadata.")
                    }
                    guard !sawExif else { throw malformed() }; sawExif = true
                } else if marker == 0xE2 {
                    guard end - start >= 14, b[start..<(start + 12)].elementsEqual(iccID) else {
                        throw CodecError(.unsupportedFeature, "Unsupported APP2 metadata.")
                    }
                    let seq = Int(b[start + 12]), count = Int(b[start + 13])
                    guard count > 0, seq > 0, seq <= count, iccCount == nil || iccCount == count,
                          iccSequences.insert(seq).inserted else { throw malformed() }
                    iccCount = count
                    iccBytes = try checkedAdd(iccBytes, end - start - 14)
                    guard iccBytes <= limits.maximumICCBytes else {
                        throw CodecError(.resourceLimitExceeded, "JPEG ICC limit exceeded.")
                    }
                } else if marker == 0xEE {
                    guard end - start == 12, b[start..<(start + 5)].elementsEqual(Array("Adobe".utf8)),
                          b[end - 1] == 1 || b[end - 1] == 0 else {
                        throw CodecError(.unsupportedFeature, "Unsupported Adobe colour transform.")
                    }
                    guard adobeTransform == nil else { throw malformed() }
                    adobeTransform = b[end - 1]
                } else if marker != 0xE0 {
                    throw CodecError(.unsupportedFeature, "JPEG contains metadata the adapter cannot preserve.")
                }
            default:
                throw CodecError(.unsupportedFeature, "Unsupported JPEG marker.")
            }
            p = end
            if marker == 0xDA {
                while p < b.count {
                    if p % 4096 == 0 { try NativeOperation.check() }
                    if b[p] != 255 { p += 1; continue }
                    guard p + 1 < b.count else { throw malformed() }
                    if b[p + 1] == 0 || (208...215).contains(b[p + 1]) { p += 2 }
                    else { break }
                }
            }
        }
        throw malformed()
    }
}
