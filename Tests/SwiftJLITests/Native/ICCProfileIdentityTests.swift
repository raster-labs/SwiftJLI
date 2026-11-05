// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftJLI

@Suite struct ICCProfileIdentityTests {
    @Test func portableIdentifierPreservesTheCompleteXYBProfile() {
        // Frozen from the predecessor b6df774a3c3ecdf4b98971f31543fdd18074ace2
        // synthetic xyb8-512 JPEG (SHA256 f4c4c31b447448f8c9ff7f1849fb70f9
        // fccaa9b746cabdcdf3bc75b34abf8a33), retained in the 2026-11-02 corpus.
        let bytes = XYBICCProfile.data
        #expect(bytes.count == 728)
        let digest = CorpusSHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "5c92716246d79febe3a40382562a4de5450610e2a1ae5f6d19ea3e0a23a444f9")
        #expect(bytes[84..<100].map { String(format: "%02x", $0) }.joined()
            == "20767ea4d321b010a0e3ba434582442c")
    }
}
