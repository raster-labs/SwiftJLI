# Release procedure for SwiftJLI

Prepared for SwiftJLI stable releases following the Swift Image Compression Suite release procedure (shared contract `0.10.0`, Apple OS `26.0` deployment floor, Swift `6.2` tools minimum / Swift `6.4` qualified in Swift `6` language mode).

## Preconditions the release task must verify first

1. **Continuous integration executes.** CI workflows execute with non-zero steps.
2. **Private vulnerability reporting is enabled** on the repository (SECURITY.md): `gh api repos/raster-labs/SwiftJLI/private-vulnerability-reporting` must report `"enabled": true`.
3. **The owner has assigned the release task explicitly.**

## Gates at the release commit

| Gate | Command | Pass condition |
| --- | --- | --- |
| Shared contract manifest | `(cd Documentation && shasum -a 256 -c COMMON_CONTRACT_SHA256.txt)` | 7 of 7 OK |
| Full Release test suite | `xcrun swift test -c release` | All tests pass, 0 failures |
| CLI conformance | `python3 Scripts/test-cli.py --binary <release-binary> --output <scratch>` | All process checks pass |
| Staged manual & executable | `./Scripts/install-cli.sh --binary <release-binary> --prefix /usr/local --destdir <stage>` | Staged installation succeeds |
| Independent consumer | `xcrun swift run --package-path Examples/IndependentConsumer` | Standalone consumer passes all operations |

## Version and tag steps

1. Set `VERSION` to the release version (e.g. `2.0.1`); update the version string in `Sources/SwiftJLICLI/main.swift`, the `.TH` line of `ManPages/swiftjli-cli.1`, the version lines in `README.md` and `CLI.md`, and add the top `CHANGELOG.md` entry `## <version> — <date>` with executed gates listed.
2. Record release gate evidence in `Documentation/RELEASE-v<version>.md`.
3. Commit as `Release <version>` and push/merge to `main`.
4. Tag the commit with an annotated tag and push it:
   ```sh
   git tag -a v<version> -m "SwiftJLI <version>" <commit> && git push origin v<version>
   ```
5. Create the GitHub release from the tag with the CHANGELOG entry as its body:
   ```sh
   gh release create v<version> --title "SwiftJLI v<version>" --notes-file <notes>
   ```
6. Verify package consumption from the tag with a fresh package using `.package(url: ..., from: "<version>")`.
