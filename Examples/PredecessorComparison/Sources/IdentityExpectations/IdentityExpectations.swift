// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum IdentityExpectations {
    private static let corrected: Set<String> = [
        "gradient-256/default-420", "gradient-256/annexK-420",
        "noise-256/default-420", "noise-256/annexK-420",
        "gradient-67x61/default-420", "gradient-67x61/annexK-420",
        "color12-grad-64/sof1-lossy"
    ]
    #if CENTERED_REFERENCE
    public static let summary = "71 encoded records and 7 corrected decoded records against JLISwift 981da4ef"
    #else
    public static let summary = "71 encoded records and 64 unchanged decoded records against JLISwift 0a4ded0"
    #endif

    public static func failures(expected: [String], actual: [String]) -> [String] {
        guard expected.count == 71, actual.count == 71 else { return ["Expected 71 records per codec"] }
        let names = Set(actual.compactMap { $0.split(separator: " ").first.map(String.init) })
        guard names.count == 71, corrected.isSubset(of: names) else { return ["Missing or duplicate identity cases"] }
        return zip(expected, actual).compactMap { old, new in
            guard !old.contains("ERROR"), !new.contains("ERROR") else { return "Codec error: \(old) / \(new)" }
            let oldParts = old.components(separatedBy: " dec=")
            let newParts = new.components(separatedBy: " dec=")
            guard oldParts.count == 2, newParts.count == 2,
                  oldParts[0] == newParts[0] else { return "Encoded identity differs: \(old) / \(new)" }
            let name = String(new.split(separator: " ")[0])
            #if CENTERED_REFERENCE
            let compareDecoded = corrected.contains(name)
            #else
            let compareDecoded = !corrected.contains(name)
            #endif
            return compareDecoded && old != new ? "Decoded identity differs: \(old) / \(new)" : nil
        }
    }
}
