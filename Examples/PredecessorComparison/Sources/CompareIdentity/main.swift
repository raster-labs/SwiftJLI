// SPDX-License-Identifier: Apache-2.0
import LegacyIdentity
import SuccessorIdentity
import IdentityExpectations

let failures = IdentityExpectations.failures(
    expected: LegacyIdentity.identityHashRecords(), actual: SuccessorIdentity.identityHashRecords())
precondition(failures.isEmpty, failures.joined(separator: "\n"))
print("Compared " + IdentityExpectations.summary + " on this platform.")
