// SPDX-License-Identifier: Apache-2.0
import Testing
import LegacyIdentity
import SuccessorIdentity

@Test func livePredecessorAndSuccessorMatchOnThisPlatform() throws {
    let old = LegacyIdentity.identityHashRecords()
    let new = SuccessorIdentity.identityHashRecords()
    try #require(old.count == 71 && new.count == 71)
    try #require(!old.contains { $0.contains("ERROR") })
    try #require(!new.contains { $0.contains("ERROR") })
    for (expected, actual) in zip(old, new) {
        #expect(expected == actual)
    }
    print("Compared 71 encoded-byte and decoded-sample records against the actual pinned predecessor on this platform.")
}
