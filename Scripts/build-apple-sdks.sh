#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Compile the library for the contract's Apple device/simulator architectures.
# This is compile evidence only; it does not claim runtime/device qualification.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift --version
xcodebuild -version
while read -r sdk triple; do
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    swift build --target SwiftJLI --configuration release --jobs 4 \
        --triple "$triple" --sdk "$sdk_path" \
        --scratch-path ".build/apple-sdk/$triple"
done <<'TARGETS'
macosx x86_64-apple-macosx26.0
iphoneos arm64-apple-ios26.0
iphonesimulator arm64-apple-ios26.0-simulator
appletvos arm64-apple-tvos26.0
appletvsimulator arm64-apple-tvos26.0-simulator
watchos arm64_32-apple-watchos26.0
watchsimulator arm64-apple-watchos26.0-simulator
xros arm64-apple-xros26.0
xrsimulator arm64-apple-xros26.0-simulator
TARGETS
