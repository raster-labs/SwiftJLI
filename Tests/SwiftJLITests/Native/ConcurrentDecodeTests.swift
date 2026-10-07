// SPDX-License-Identifier: Apache-2.0
import Testing
@testable import SwiftJLI

@Test func concurrentDCTDecodersKeepIndependentScratch() async throws {
    let source = try JLIImage(width: 32, height: 32, pixelFormat: .uint8,
                             colorModel: .grayscale, data: (0..<1024).map { UInt8(truncatingIfNeeded: $0 * 31) })
    let bytes = try JLIEncoder().encode(source)
    let scales = [1, 2, 4, 8]
    let expected = try scales.map { try JLIDecoder().decode(from: bytes, configuration: .init(scale: $0)).data }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<24 {
            group.addTask {
                for _ in 0..<4 {
                    for (index, scale) in scales.enumerated() {
                        let decoded = try JLIDecoder().decode(from: bytes, configuration: .init(scale: scale))
                        #expect(decoded.data == expected[index])
                    }
                }
            }
        }
        try await group.waitForAll()
    }
}
