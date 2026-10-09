// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.

import Foundation

enum BenchError: Error, CustomStringConvertible {
    case codecFailed(String)
    var description: String {
        switch self {
        case .codecFailed(let s): return s
        }
    }
}

/// One image to bench against.
struct TestImage {
    let name: String
    let width: Int
    let height: Int
    let rgb: [UInt8]
}

/// Synthetic test corpus. Three patterns that stress different parts of the pipeline:
/// gradient → DC + low-frequency, checker → high-frequency edges, noise → flat-spectrum
/// (worst case for compression and a stress test for entropy coding).
enum TestImages {
    static func make(size: Int) -> [TestImage] {
        return [
            gradient(name: "gradient-\(size)", size: size),
            checkerboard(name: "checker-\(size)", size: size, cell: 8),
            noise(name: "noise-\(size)", size: size),
        ]
    }

    static func gradient(name: String, size: Int) -> TestImage {
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 3
                rgb[i]     = UInt8(x * 255 / max(1, size - 1))
                rgb[i + 1] = UInt8(y * 255 / max(1, size - 1))
                rgb[i + 2] = UInt8(((x + y) % size) * 255 / max(1, size - 1))
            }
        }
        return TestImage(name: name, width: size, height: size, rgb: rgb)
    }

    static func checkerboard(name: String, size: Int, cell: Int) -> TestImage {
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 3
                let on = ((x / cell) + (y / cell)) % 2 == 0
                let v: UInt8 = on ? 230 : 25
                rgb[i] = v; rgb[i + 1] = v; rgb[i + 2] = v
            }
        }
        return TestImage(name: name, width: size, height: size, rgb: rgb)
    }

    static func noise(name: String, size: Int) -> TestImage {
        // Deterministic LCG so runs are repeatable.
        var state: UInt32 = 0xCAFEBABE
        func next() -> UInt8 {
            state = state &* 1664525 &+ 1013904223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for i in 0..<rgb.count { rgb[i] = next() }
        return TestImage(name: name, width: size, height: size, rgb: rgb)
    }

    /// Synthetic 12-bit color images (0–4095 per channel). The DICOM corpus is
    /// grayscale, so these are the only 12-bit color inputs for the cross-codec.
    static func color12(size: Int) -> [Color16Image] {
        var grad = [UInt16](repeating: 0, count: size * size * 3)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 3
                grad[i]     = UInt16(x * 4095 / max(1, size - 1))
                grad[i + 1] = UInt16(y * 4095 / max(1, size - 1))
                grad[i + 2] = UInt16(((x + y) % size) * 4095 / max(1, size - 1))
            }
        }
        var state: UInt32 = 0x12345678
        var noise = [UInt16](repeating: 0, count: size * size * 3)
        for i in 0..<noise.count {
            state = state &* 1664525 &+ 1013904223
            noise[i] = UInt16(state >> 20) & 0x0FFF
        }
        return [
            Color16Image(name: "color12-grad-\(size)", width: size, height: size, rgb: grad),
            Color16Image(name: "color12-noise-\(size)", width: size, height: size, rgb: noise),
        ]
    }
}

struct Color16Image {
    let name: String
    let width: Int
    let height: Int
    let rgb: [UInt16]   // interleaved, 0–4095
}
