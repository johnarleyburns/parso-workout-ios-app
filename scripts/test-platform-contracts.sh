#!/usr/bin/env bash
# Build the exact widget contract sources/tests without the Apple-only model
# graph. Symlinks preserve one implementation; no copied or stubbed Swift types.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cadence-platform-contracts.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
ln -s "$root/CadenceCore/Sources/CadenceFeatures" "$tmp/Sources"
ln -s "$root/CadenceCore/Tests/CadencePlatformTests" "$tmp/Tests"
cat > "$tmp/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CadencePlatformVerification", defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)], targets: [
        .target(name: "CadenceFeatures", path: "Sources",
                resources: [.process("Resources/Localizable.xcstrings")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CadencePlatformTests", dependencies: ["CadenceFeatures"],
                    path: "Tests", swiftSettings: [.swiftLanguageMode(.v6)])
    ])
SWIFT
swift test --package-path "$tmp"
