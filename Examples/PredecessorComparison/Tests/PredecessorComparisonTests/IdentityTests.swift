// SPDX-License-Identifier: Apache-2.0
import Testing
import LegacyIdentity
import SuccessorIdentity
import IdentityExpectations

@Test func livePredecessorAndSuccessorMatchOnThisPlatform() throws {
    let failures = IdentityExpectations.failures(
        expected: LegacyIdentity.identityHashRecords(), actual: SuccessorIdentity.identityHashRecords())
    for failure in failures { Issue.record(Comment(rawValue: failure)) }
    #expect(failures.isEmpty)
    print("Compared " + IdentityExpectations.summary + " on this platform.")
}
