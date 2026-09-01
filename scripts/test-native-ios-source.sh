#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
for command_name in ditto swift; do
    sfiora_require_command "${command_name}"
done

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-ios-source-tests.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT

mkdir -p \
    "${temporary_dir}/Sources" \
    "${temporary_dir}/Tests/SfioraTests/fixtures"
ditto \
    "${sfiora_root}/native/ios/Sources/Sfiora" \
    "${temporary_dir}/Sources/Sfiora"
ditto \
    "${sfiora_root}/tests/ios" \
    "${temporary_dir}/Tests/SfioraTests"
cp \
    "${sfiora_root}/tests/fixtures/ndef-vectors.json" \
    "${temporary_dir}/Tests/SfioraTests/fixtures/ndef-vectors.json"

cat > "${temporary_dir}/Package.swift" <<EOF
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SfioraSourceTests",
    platforms: [
        .iOS(.v${sfiora_ios_minimum%%.*})
    ],
    targets: [
        .target(
            name: "Sfiora",
            path: "Sources/Sfiora"
        ),
        .testTarget(
            name: "SfioraTests",
            dependencies: ["Sfiora"],
            path: "Tests/SfioraTests",
            resources: [
                .process("fixtures/ndef-vectors.json")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
EOF

swift test \
    --package-path "${temporary_dir}" \
    -Xswiftc -warnings-as-errors

printf '%s\n' "Verified current Sfiora iOS source tests."
