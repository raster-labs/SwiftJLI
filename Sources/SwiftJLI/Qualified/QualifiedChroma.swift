// SPDX-License-Identifier: Apache-2.0
// Copyright 2024 Raster Lab. All rights reserved.
// Adapted caller-storage subset from raster-labs/JLISwift
// b6df774a3c3ecdf4b98971f31543fdd18074ace2. See Documentation/Migration/QualifiedJPEG.md.
enum QualifiedChromaSampling {
    static func bilinear(_ v00: Float, _ v10: Float, _ v01: Float, _ v11: Float,
                         fx: Float, fy: Float) -> Float {
        v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) +
        v01 * (1 - fx) * fy + v11 * fx * fy
    }
    static func jpegCenteredSample(x: Int, y: Int, width: Int, height: Int,
                                   h2: Bool, v2: Bool, sample: (Int, Int) -> Float) -> Float {
        if !h2 && !v2 { return sample(min(x, width - 1), min(y, height - 1)).rounded() }
        let fancy = !h2 || width > 2
        let cy = min(v2 ? y / 2 : y, height - 1)
        let ny = min(max(cy + (y.isMultiple(of: 2) ? -1 : 1), 0), height - 1)
        let cx = min(h2 ? x / 2 : x, width - 1)
        let nx = min(max(cx + (x.isMultiple(of: 2) ? -1 : 1), 0), width - 1)
                        let current = Int(sample(cx, cy).rounded())
                        let value: Int
                        if !fancy {
                            value = current
                        } else if h2 && v2 {
                            let near = 3 * current + Int(sample(cx, ny).rounded())
                            let far = 3 * Int(sample(nx, cy).rounded()) + Int(sample(nx, ny).rounded())
                            value = (3 * near + far + (x.isMultiple(of: 2) ? 8 : 7)) >> 4
                        } else if h2 {
                            value = (3 * current + Int(sample(nx, cy).rounded())
                                     + (x.isMultiple(of: 2) ? 1 : 2)) >> 2
                        } else {
                            value = (3 * current + Int(sample(cx, ny).rounded())
                                     + (y.isMultiple(of: 2) ? 1 : 2)) >> 2
                        }
        return Float(value)
    }
    static func upsampleInPlaceCore(_ plane: UnsafeMutableBufferPointer<Float>, width: Int, height: Int,
        targetWidth: Int, targetHeight: Int, horizontalSampling: Int, verticalSampling: Int,
        maximumHorizontalSampling: Int, maximumVerticalSampling: Int, centered: Bool,
        rowScratch: UnsafeMutableBufferPointer<Float>, cancellation: QualifiedCancellation = .never) -> QualifiedOutcome<Void> {
        precondition(plane.count >= targetWidth * targetHeight && rowScratch.count >= 3 * width)
        let h1 = horizontalSampling == maximumHorizontalSampling
        let v1 = verticalSampling == maximumVerticalSampling
        let h2 = horizontalSampling * 2 == maximumHorizontalSampling
        let v2 = verticalSampling * 2 == maximumVerticalSampling
        let jpeg = centered && (h1 || h2) && (v1 || v2)
        let xScale = Float(width - 1) / Float(max(1, targetWidth - 1))
        let yScale = Float(height - 1) / Float(max(1, targetHeight - 1))
        var ids = (a: -1, b: -1, c: -1)
        func slot(_ row: Int) -> Int? {
            if ids.a == row { return 0 }; if ids.b == row { return 1 }; if ids.c == row { return 2 }
            return nil
        }
        for y in stride(from: targetHeight - 1, through: 0, by: -1) {
            if case .failure(let failure) = cancellation.check() { return .failure(failure) }
            let srcY = Float(y) * yScale
            let row0: Int, row1: Int
            if jpeg {
                row0 = min(v2 ? y / 2 : y, height - 1)
                row1 = min(max(row0 + (y.isMultiple(of: 2) ? -1 : 1), 0), height - 1)
            } else {
                row0 = min(Int(srcY), height - 1); row1 = min(row0 + 1, height - 1)
            }
            func cache(_ row: Int) {
                if slot(row) != nil { return }
                let index: Int
                if ids.a != row0 && ids.a != row1 { index = 0; ids.a = row }
                else if ids.b != row0 && ids.b != row1 { index = 1; ids.b = row }
                else { index = 2; ids.c = row }
                for x in 0..<width { rowScratch[index * width + x] = plane[row * width + x] }
            }
            cache(row0); cache(row1)
            guard let slot0 = slot(row0), let slot1 = slot(row1) else { preconditionFailure("Missing cached row") }
            let fy = srcY - Float(row0)
            for x in 0..<targetWidth {
                let value: Float
                if jpeg {
                    value = jpegCenteredSample(x: x, y: y, width: width, height: height, h2: h2, v2: v2) { sx, sy in
                        rowScratch[(sy == row0 ? slot0 : slot1) * width + sx]
                    }
                } else if width == targetWidth && height == targetHeight {
                    value = rowScratch[slot0 * width + x]
                } else {
                    let srcX = Float(x) * xScale
                    let x0 = min(Int(srcX), width - 1), x1 = min(x0 + 1, width - 1)
                    value = bilinear(rowScratch[slot0 * width + x0], rowScratch[slot0 * width + x1],
                        rowScratch[slot1 * width + x0], rowScratch[slot1 * width + x1], fx: srcX - Float(x0), fy: fy)
                }
                plane[y * targetWidth + x] = value
            }
        }
        return .success(())
    }
}
