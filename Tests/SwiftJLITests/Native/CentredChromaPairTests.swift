// SPDX-License-Identifier: MIT
import Testing
@testable import SwiftJLI

@Suite struct CentredChromaPairTests {
    // Retained per-output-pixel formula: independent of the rolling pair state.
    private func reference(_ plane: [Float], width: Int, height: Int,
                           outputWidth: Int, outputHeight: Int, h2: Bool, v2: Bool) -> [Float] {
        let samples = plane.map { Int($0.rounded()) }
        if !h2 && !v2 { return samples.map(Float.init) }
        return (0..<(outputWidth * outputHeight)).map { index in
            let x = index % outputWidth, y = index / outputWidth
            let cx = min(h2 ? x / 2 : x, width - 1)
            let cy = min(v2 ? y / 2 : y, height - 1)
            let nx = min(max(cx + (x % 2 == 0 ? -1 : 1), 0), width - 1)
            let ny = min(max(cy + (y % 2 == 0 ? -1 : 1), 0), height - 1)
            let current = samples[cy * width + cx]
            if h2 && width <= 2 { return Float(current) }
            if h2 && v2 {
                let near = 3 * current + samples[ny * width + cx]
                let far = 3 * samples[cy * width + nx] + samples[ny * width + nx]
                return Float((3 * near + far + (x % 2 == 0 ? 8 : 7)) >> 4)
            }
            if h2 { return Float((3 * current + samples[cy * width + nx] + (x % 2 == 0 ? 1 : 2)) >> 2) }
            return Float((3 * current + samples[ny * width + cx] + (y % 2 == 0 ? 1 : 2)) >> 2)
        }
    }

    @Test func pairsKeepIntegerRoundingAtOddEdgesAndNarrowPlanes() throws {
        for width in [1, 2, 3, 4, 7, 17] {
            for height in [1, 2, 3, 9] {
                for h2 in [false, true] { for v2 in [false, true] {
                    for odd in [false, true] {
                        let outputWidth = width * (h2 ? 2 : 1) - (h2 && odd ? 1 : 0)
                        let outputHeight = height * (v2 ? 2 : 1) - (v2 && odd ? 1 : 0)
                        let plane = (0..<(width * height)).map { index in
                            let fraction: Float = index % 3 == 0 ? 0.375 : index % 3 == 1 ? 0.5 : -0.5
                            return Float((index * 3187 + 911) % 4096) + fraction
                        }
                        let actual = try ChromaSampling.upsampleJPEG(plane, width: width, height: height,
                            targetWidth: outputWidth, targetHeight: outputHeight,
                            horizontalSampling: 1, verticalSampling: 1,
                            maximumHorizontalSampling: h2 ? 2 : 1, maximumVerticalSampling: v2 ? 2 : 1)
                        let expected = reference(plane, width: width, height: height,
                            outputWidth: outputWidth, outputHeight: outputHeight, h2: h2, v2: v2)
                        #expect(actual.map(\.bitPattern) == expected.map(\.bitPattern))
                    }
                } }
            }
        }
    }

    @Test func joinedRowsMatchReferenceForEachSamplingDirection() throws {
        let width = 257, height = 129
        let plane = (0..<(width * height)).map { Float(($0 * 71) % 4096) + 0.5 }
        for h2 in [false, true] { for v2 in [false, true] where h2 || v2 {
            let outputWidth = width * (h2 ? 2 : 1) - (h2 ? 1 : 0)
            let outputHeight = height * (v2 ? 2 : 1) - (v2 ? 1 : 0)
            let expected = reference(plane, width: width, height: height,
                outputWidth: outputWidth, outputHeight: outputHeight, h2: h2, v2: v2)
            for workers in [1, 4] {
                let actual = try NativeOperation.$current.withValue(
                    .init(seconds: 120, backend: .scalarCPU, maximumWorkers: workers)) {
                        try ChromaSampling.upsampleJPEG(plane, width: width, height: height,
                            targetWidth: outputWidth, targetHeight: outputHeight,
                            horizontalSampling: 1, verticalSampling: 1,
                            maximumHorizontalSampling: h2 ? 2 : 1, maximumVerticalSampling: v2 ? 2 : 1)
                    }
                #expect(actual.map(\.bitPattern) == expected.map(\.bitPattern))
            }
        } }
    }
}
