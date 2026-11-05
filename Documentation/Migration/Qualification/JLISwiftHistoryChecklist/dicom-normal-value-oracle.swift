import Foundation

@main struct DICOMNormalValueOracle {
    static func main() throws {
        var cases = 0, failures = 0, canonicalFailures = 0
        for allocated in [8, 16] {
            for stored in (allocated == 8 ? [2, 4, 8] : [8, 12, 16]) {
                for highBit in (stored - 1)..<allocated {
                    for signed in [false, true] {
                        let maximum = (1 << stored) - 1
                        let values = signed ? [-(1 << (stored - 1)), -1, 0, 1, (1 << (stored - 1)) - 1]
                                            : [0, 1, maximum / 2, maximum - 1, maximum]
                        let shift = highBit + 1 - stored
                        let dataMask = maximum << shift
                        let containerMask = (1 << allocated) - 1
                        var bytes: [UInt8] = []
                        for sample in values {
                            let field = (sample & maximum) << shift
                            let unused = (containerMask ^ dataMask) & 0xAAAA
                            let raw = field | unused
                            bytes.append(UInt8(raw & 255))
                            if allocated == 16 { bytes.append(UInt8(raw >> 8)) }
                        }
                        let image = DICOMImage(width: values.count, height: 1, samplesPerPixel: 1,
                            bitsAllocated: allocated, bitsStored: stored, pixelRepresentation: signed ? 1 : 0,
                            highBit: highBit, planarConfiguration: 0, photometric: "MONOCHROME2", modality: "",
                            windowCenter: nil, windowWidth: nil, rescaleSlope: 2, rescaleIntercept: -1024,
                            pixelData: bytes, transferSyntax: "1.2.840.10008.1.2.1")
                        let expected = values.map { Double($0 * 2 - 1024) }
                        let actual = image.decodeIntensitiesForRenderer()
                        cases += 1
                        if actual != expected {
                            failures += 1
                            if shift == 0 { canonicalFailures += 1 }
                            print("MISMATCH allocated=\(allocated) stored=\(stored) highBit=\(highBit) signed=\(signed) expected=\(expected) actual=\(actual)")
                        }
                    }
                }
            }
        }
        let result: [String: Any] = ["cases": cases, "failures": failures, "canonical_failures": canonicalFailures,
            "coverage": "Small ordinary sample values, unused-bit masking, signed interpretation and modality rescale. Shifted layouts are legacy compatibility, not current canonical DICOM output."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if failures > 0 { Foundation.exit(1) }
    }
}
