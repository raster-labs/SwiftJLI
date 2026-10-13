// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing

@Test func predecessorIdentityMatrixIsRetained() throws {
    let url = try #require(Bundle.module.url(forResource: "predecessor-identity-macos-arm64", withExtension: "txt", subdirectory: "Fixtures"))
    let baseline = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        .filter { !$0.hasPrefix("AGGREGATE ") }
    let actual = identityHashRecords()
    // Only these seven decoded hashes changed with the centred-chroma fix.
    // Their replacement oracle was generated independently by JLISwift v0.5.2;
    // the historical 71-record fixture and every encoder hash remain intact.
    let correctedURL = try #require(Bundle.module.url(forResource: "centered-chroma-identity-macos-arm64",
        withExtension: "txt", subdirectory: "Fixtures"))
    let corrections = try String(contentsOf: correctedURL, encoding: .utf8).split(separator: "\n").map(String.init)
    #expect(corrections.count == 7)
    #expect(baseline.count == 71)
    #expect(actual.count == baseline.count)
    #expect(!actual.contains { $0.contains("ERROR") })
    for (expected, observed) in zip(baseline, actual) {
        let name = expected.split(separator: " ")[0]
        #expect(observed.split(separator: " ").first == name)
        // SOF3 is integer-exact across platforms, including nonzero point
        // transforms and signed raw-bit legacy cases. This does not advertise
        // portable signed JPEG interpretation through the new public API.
        if name.contains("/lossless") || name.contains("/nearloss") {
            #expect(expected == observed, "Predecessor SOF3 identity changed: \(name)")
        }
        #if os(macOS) && canImport(Accelerate) && arch(arm64)
        // Floating-point DSP hashes are platform-specific. Keep all unaffected
        // outputs frozen and verify the corrected output against the new oracle.
        let corrected = corrections.first { $0.split(separator: " ").first == name }
        if let corrected {
            #expect(corrected.components(separatedBy: " dec=")[0] == expected.components(separatedBy: " dec=")[0])
        }
        #expect((corrected ?? expected) == observed, "Predecessor macOS ARM64 identity changed: \(name)")
        #endif
    }
}
