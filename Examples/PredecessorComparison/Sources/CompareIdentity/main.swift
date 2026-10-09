// SPDX-License-Identifier: Apache-2.0
import LegacyIdentity
import SuccessorIdentity

let expected = LegacyIdentity.identityHashRecords()
let actual = SuccessorIdentity.identityHashRecords()
precondition(expected.count == 71 && actual.count == 71)
precondition(!expected.contains { $0.contains("ERROR") })
precondition(expected == actual, "The actual predecessor differs on this platform")
print("All 71 same-platform predecessor identity records match.")
