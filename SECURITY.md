# Security policy and implementation requirements

Status: development codec implementation; [stable-release acceptance](Documentation/Migration/ACCEPTANCE.md) remains open. No successor binary release exists and no vulnerability response time is promised here.

## Reporting

The prepared reporting channel is [GitHub private vulnerability reporting](https://github.com/raster-labs/SwiftJLI/security/advisories/new), but repository-admin activation is still required. The 12 October API check reports it disabled; the current automation account has push access without admin access. Until activation, use an already established private channel to a repository maintainer. Do not assume the advisory link is accepting private reports. Do not post exploitable payloads, credentials or patient information in a public issue. No separate security mailbox or response-time guarantee is advertised.

Include affected version/commit, platform, a minimal safe reproducer, expected/actual behaviour and impact. Use synthetic data where possible. Keep the report private while maintainers reproduce the issue and prepare a correction. Coordinate disclosure through the private advisory thread.

## Supported versions

| Version or branch | Security-fix policy |
| --- | --- |
| Current development main and active 1.1.0 release candidate | Reports are investigated; corrections target main and the active candidate. Development snapshots are not stable releases. |
| Latest 1.1.x patch, once 1.1.0 is released | Supported for security fixes; users of earlier 1.1.x patches should upgrade to the latest patch. |
| Older development snapshots and unmaintained feature branches | No separate backports; reproduce on the current candidate and upgrade. |
| JLISwift predecessor | Governed by the predecessor repository's own security and maintenance policy. |

No stable SwiftJLI release has been published. This policy prepares the reporting
and maintenance process; it does not waive remaining release qualification or
change the predecessor's support commitments.

## Threat model

Treat every compressed image, metadata field, interchange header and caller-supplied descriptor as untrusted. Attackers may attempt out-of-bounds access, integer overflow, decompression bombs, pathological entropy work, deeply nested containers, unbounded tasks/caches, malformed colour profiles, unsafe external references or leakage of previous frame memory. Core codecs do not access the network, spawn reference codecs or interpret embedded code.

Enforce the resource, deadline and ownership rules in the common contracts before allocating and while processing. Check slice indices and offset bases. Bound metadata, frame/component/tile counts and parse depth. Reject unsupported essential features. Do not use assertions/preconditions to validate hostile input. Do not emit success after partial decode or cancellation.

Use synthetic fixtures and sanitised diagnostics. Do not log raw images, patient fields, full filesystem paths or memory addresses by default. Initialise exported padding and prevent pool reuse while readers remain. Use scoped filesystem operations only in the CLI; reject detached input references/URLs in the initial stream profile. Atomic final-output publication and overwrite checks must not become path traversal or symlink vulnerabilities.

## Required verification

Run parser/descriptor mutation tests, bounded fuzzing, address/race checks on supported environments and allocation/cancellation stress. Record and fix crash/hang seeds. Review unsafe bridges and native kernels. Check third-party development tools/dependencies and pin reproducible versions. No unresolved severe memory-safety, data-corruption or input-triggered denial-of-service finding is acceptable at stable release.

Correctness and security gates cannot be waived by a benchmark improvement. See `Documentation/TESTING.md` and `Documentation/PERFORMANCE.md` for evidence requirements.
