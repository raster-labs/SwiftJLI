import Foundation
@testable import SwiftJLI

@main struct Verify {
    static func markers(_ b: [UInt8]) -> [(Int, Int, Int)] {
        var p = 2, result: [(Int, Int, Int)] = []
        while p + 3 < b.count {
            let marker = Int(b[p + 1]), length = Int(b[p + 2]) * 256 + Int(b[p + 3])
            result.append((p, marker, length))
            if marker == 0xda { break }
            p += length + 2
        }
        return result
    }
    static func main() async throws {
        let decoder = try SwiftJLI.Decoder()
        for (name, policy) in [("scalar", ExecutionPolicy.scalarCPU), ("automatic", .automatic)] {
            var failed = 0
            for f in ChromaReferenceFixtures.all {
                let jpeg = Data(base64Encoded: f.jpeg)!, rgb = Array(Data(base64Encoded: f.rgb)!)
                let result = try await decoder.decode(jpeg, options: .init(executionPolicy: policy))
                let actual = try result.image.storage.withUnsafeBytes { Array($0) }
                let differences = zip(actual, rgb).map { abs(Int($0) - Int($1)) }
                let maximum = differences.max() ?? 0
                let valid = actual.count == rgb.count && result.image.descriptor.width == f.width && result.image.descriptor.height == f.height
                if maximum > 3 || !valid { failed += 1 }
                print("CHROMA \(name) \(f.name) max=\(maximum) over3=\(differences.filter { $0 > 3 }.count) geometry=\(valid)")
            }
            print("CHROMA_SUMMARY \(name) failures=\(failed)/\(ChromaReferenceFixtures.all.count)")
        }
        let grey = try JLIImage(width: 8, height: 8, pixelFormat: .uint8, colorModel: .grayscale, data: [UInt8](repeating: 73, count: 64))
        let stream = try JLIEncoder().encode(grey)
        func check(_ name: String, _ bytes: [UInt8], limits: ResourceLimits = .default) async {
            do {
                let output = try await decoder.decode(Data(bytes), options: .init(resourceLimits: limits))
                let first = try output.image.storage.withUnsafeBytes { Array($0.prefix(3)) }
                print("CASE \(name) ACCEPT colour=\(output.image.descriptor.colour) first=\(first)")
            } catch { print("CASE \(name) REJECT \(error)") }
        }
        await check("valid-grey", stream)
        await check("missing-EOI", Array(stream.dropLast(2)))
        await check("concatenated", stream + stream)
        await check("trailing-garbage", stream + [1,2])
        let odd = stream.count % 2 == 1 ? stream : Array(stream.prefix(2)) + [255,224,0,3,0] + Array(stream.dropFirst(2))
        print("DICOM_BASE_LENGTH \(odd.count)")
        await check("odd-unpadded", odd)
        await check("legal-DICOM-zero-pad", odd + [0])
        await check("compressed-limit", stream, limits: try .init(maximumCompressedBytes: 2))
        await check("pixel-limit", stream, limits: try .init(maximumPixels: 63))
        await check("decoded-byte-limit", stream, limits: try .init(maximumDecodedBytes: 63))
        let frame = markers(stream).first { (0xc0...0xc3).contains($0.1) }!
        await check("duplicate-SOF", Array(stream.prefix(frame.0)) + Array(stream[frame.0..<(frame.0 + frame.2 + 2)]) + Array(stream.dropFirst(frame.0)))

        let samples: [UInt8] = (0..<64).flatMap { _ in [UInt8(210),70,25] }
        let planes = try JLIImage(width: 8, height: 8, pixelFormat: .uint8, colorModel: .yCbCr, data: samples)
        var config = JLIEncoderConfiguration.default
        config.chromaSubsampling = .yuv444; config.quality = 100
        let dct = try JLIEncoder().encode(planes, configuration: config)
        let adobe: [UInt8] = [255,238,0,14,65,100,111,98,101,0,100,0,0,0,0,0]
        await check("raw-RGB-Adobe0", Array(dct.prefix(2)) + adobe + Array(dct.dropFirst(2)))
        var explicitRGB = dct
        for (p, m, _) in markers(explicitRGB) {
            if (0xc0...0xc3).contains(m) {
                for c in 0..<3 { explicitRGB[p + 10 + c * 3] = [82,71,66][c] }
            } else if m == 0xda {
                for c in 0..<3 { explicitRGB[p + 5 + c * 2] = [82,71,66][c] }
            }
        }
        await check("raw-RGB-component-IDs", explicitRGB)
        let rgbImage = try JLIImage(width: 8, height: 8, pixelFormat: .uint8, colorModel: .rgb, data: samples)
        var losslessCfg = JLIEncoderConfiguration.default
        losslessCfg.lossless = true; losslessCfg.losslessPrecision = 8
        var lossless = try JLIEncoder().encode(rgbImage, configuration: losslessCfg)
        for (p,m,_) in markers(lossless) {
            if m == 0xc3 { for c in 0..<3 { lossless[p + 10 + c * 3] = [82,71,66][c] } }
            if m == 0xda { for c in 0..<3 { lossless[p + 5 + c * 2] = [82,71,66][c] } }
        }
        await check("valid-interleaved-lossless", lossless)
        let sos = markers(lossless).first { $0.1 == 0xda }!
        var partial = lossless
        partial.removeSubrange((sos.0 + 7)..<(sos.0 + 11))
        partial[sos.0 + 3] -= 4; partial[sos.0 + 4] = 1
        await check("lossless-incomplete-component-scan", partial)
        let plane = try PlaneDescriptor(width: 8, height: 8, components: [0,1,2], sampleStride: 1, pixelStride: 3, rowBytes: 24, byteCount: 192)
        let descriptor = try ImageDescriptor(width: 8, height: 8, storageBits: 8, meaningfulBits: 8, components: [.red,.green,.blue], colour: .rgb, planes: [plane])
        do {
            _ = try await decoder.decode(Data(stream), into: ImageDestination.allocate(descriptor: descriptor))
            print("CASE grey-as-RGB-destination ACCEPT")
        } catch { print("CASE grey-as-RGB-destination REJECT \(error)") }
    }
}
