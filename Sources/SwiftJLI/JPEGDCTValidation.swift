// SPDX-License-Identifier: Apache-2.0
import Foundation

extension JPEGCodec {
    /// Validate the kernel's supported scan topology before allocating coefficient
    /// planes. In particular, the native progressive DC walk is interleaved.
    static func validateDCT(_ parsed: ParsedJPEG) throws {
        let f = parsed.frameInfo, ids = f.components.map(\.id)
        func malformed() -> CodecError { .init(.malformedInput, "Invalid JPEG DCT tables or scan progression.") }
        guard f.precision == 8 || f.precision == 12, ids.count == 1 || ids == [1, 2, 3],
              parsed.iccProfile != XYBICCProfile.data else {
            throw CodecError(.unsupportedFeature, "DCT requires 8/12-bit greyscale or YCbCr JPEG.")
        }
        for (i, c) in f.components.enumerated() {
            guard (1...2).contains(c.horizontalSampling), (1...2).contains(c.verticalSampling),
                  (i == 0 && ids.count == 3) || (c.horizontalSampling == 1 && c.verticalSampling == 1) else {
                throw CodecError(.unsupportedFeature, "Unsupported DCT component sampling.")
            }
            guard parsed.quantTables.indices.contains(c.quantTableIndex),
                  parsed.quantTables[c.quantTableIndex].count == 64,
                  parsed.quantTables[c.quantTableIndex].allSatisfy({ $0 > 0 }) else { throw malformed() }
        }
        var levels = [[Int]](repeating: [Int](repeating: -1, count: 64), count: ids.count)
        for scan in parsed.scans {
            let h = scan.header, selectors = h.components.map(\.componentSelector)
            guard !selectors.isEmpty, Set(selectors).count == selectors.count,
                  selectors.allSatisfy({ ids.contains($0) }),
                  (0...63).contains(h.spectralStart), (h.spectralStart...63).contains(h.spectralEnd),
                  (0...13).contains(h.successiveApproxHigh), (0...13).contains(h.successiveApproxLow) else { throw malformed() }
            if !f.isProgressive {
                guard parsed.scans.count == 1, selectors == ids, h.spectralStart == 0, h.spectralEnd == 63,
                      h.successiveApproxHigh == 0, h.successiveApproxLow == 0 else { throw malformed() }
            } else if h.spectralStart == 0 {
                guard h.spectralEnd == 0, selectors == ids else {
                    throw CodecError(.unsupportedFeature, "Progressive DC scans must contain all components in frame order.")
                }
            } else {
                guard selectors.count == 1 else { throw malformed() }
            }
            for c in h.components {
                guard let index = ids.firstIndex(of: c.componentSelector) else { throw malformed() }
                if h.spectralStart == 0 && h.successiveApproxHigh == 0 {
                    guard let t = scan.dcTables[c.dcTableId], t.values.allSatisfy({ $0 <= (f.precision == 8 ? 11 : 15) }) else { throw malformed() }
                }
                if h.spectralEnd > 0 {
                    guard let t = scan.acTables[c.acTableId], t.values.allSatisfy({ ($0 & 15) <= (f.precision == 8 ? 10 : 14) }) else { throw malformed() }
                }
                if f.isProgressive {
                    for k in h.spectralStart...h.spectralEnd {
                        let previous = levels[index][k]
                        guard h.successiveApproxHigh == 0 ? previous == -1
                            : previous == h.successiveApproxHigh && h.successiveApproxLow == previous - 1 else { throw malformed() }
                        levels[index][k] = h.successiveApproxLow
                    }
                }
            }
        }
        guard !parsed.scans.isEmpty, !f.isProgressive || levels.allSatisfy({ $0[0] >= 0 }) else { throw malformed() }
    }
}
