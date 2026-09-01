#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

for command_name in git plutil shasum xattr xcodebuild zip; do
    sfiora_require_command "${command_name}"
done

ios_dir="${sfiora_root}/native/ios"
project_path="${ios_dir}/Sfiora.xcodeproj"
artifact_dir="${sfiora_root}/dist/native-ios"
artifact_name="sfiora-${sfiora_version}.xcframework.zip"
artifact_path="${artifact_dir}/${artifact_name}"
accepted_archive="${SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP:-}"
accepted_sha256="${SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256:-}"
accepted_source_commit="${SFIORA_IOS_ACCEPTED_SOURCE_COMMIT:-}"
ios_binary_inputs=(
    LICENSE
    plugin.json
    native/ios
    scripts/package-native-ios.sh
    scripts/release-common.sh
)

accepted_value_count=0
for accepted_value in "${accepted_archive}" "${accepted_sha256}" "${accepted_source_commit}"; do
    if [[ -n "${accepted_value}" ]]; then
        accepted_value_count=$((accepted_value_count + 1))
    fi
done
if [[ ${accepted_value_count} -ne 0 && ${accepted_value_count} -ne 3 ]]; then
    echo "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP, SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256," >&2
    echo "and SFIORA_IOS_ACCEPTED_SOURCE_COMMIT must be supplied together." >&2
    exit 1
fi

if [[ ${accepted_value_count} -eq 3 ]]; then
    if [[ "${accepted_archive}" != /* || ! -f "${accepted_archive}" ]]; then
        echo "Accepted Sfiora XCFramework must be an existing absolute file path." >&2
        exit 1
    fi
    if [[ ! "${accepted_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256 must be a lowercase SHA-256." >&2
        exit 1
    fi
    if [[ ! "${accepted_source_commit}" =~ ^[0-9a-f]{40}$ ]] \
        || ! git -C "${sfiora_root}" cat-file -e "${accepted_source_commit}^{commit}" 2>/dev/null; then
        echo "SFIORA_IOS_ACCEPTED_SOURCE_COMMIT must identify a local source commit." >&2
        exit 1
    fi
    if ! git -C "${sfiora_root}" merge-base --is-ancestor \
        "${accepted_source_commit}" HEAD; then
        echo "Accepted iOS source commit is not an ancestor of the current release commit." >&2
        exit 1
    fi
    if ! git -C "${sfiora_root}" diff --quiet \
        "${accepted_source_commit}" HEAD -- "${ios_binary_inputs[@]}" \
        || ! git -C "${sfiora_root}" diff --quiet -- "${ios_binary_inputs[@]}" \
        || ! git -C "${sfiora_root}" diff --cached --quiet -- "${ios_binary_inputs[@]}"; then
        echo "Sfiora native iOS inputs changed after the accepted binary was built." >&2
        exit 1
    fi
    actual_sha256="$(sfiora_sha256 "${accepted_archive}")"
    if [[ "${actual_sha256}" != "${accepted_sha256}" ]]; then
        echo "Accepted Sfiora XCFramework checksum differs." >&2
        echo "Expected: ${accepted_sha256}" >&2
        echo "Actual:   ${actual_sha256}" >&2
        exit 1
    fi

    mkdir -p "${artifact_dir}"
    accepted_absolute="$(cd "$(dirname "${accepted_archive}")" && pwd -P)/$(basename "${accepted_archive}")"
    artifact_absolute="$(cd "${artifact_dir}" && pwd -P)/${artifact_name}"
    if [[ "${accepted_absolute}" != "${artifact_absolute}" ]]; then
        staged_archive="$(mktemp "${artifact_dir}/.sfiora-ios-promote.XXXXXX")"
        if ! cp "${accepted_archive}" "${staged_archive}" \
            || [[ "$(sfiora_sha256 "${staged_archive}")" != "${accepted_sha256}" ]] \
            || ! mv -f "${staged_archive}" "${artifact_path}"; then
            echo "Unable to promote the accepted Sfiora XCFramework." >&2
            find "${staged_archive}" -delete 2>/dev/null || true
            exit 1
        fi
    fi
    sfiora_write_checksum "${artifact_path}"
    printf '%s\n' "${artifact_path}"
    exit 0
fi

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-ios-package.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
device_archive="${temporary_dir}/Sfiora-iOS.xcarchive"
simulator_archive="${temporary_dir}/Sfiora-Simulator.xcarchive"
xcframework_path="${temporary_dir}/Sfiora.xcframework"

xcodebuild -quiet archive \
    -project "${project_path}" \
    -scheme Sfiora \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "${device_archive}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MARKETING_VERSION="${sfiora_version}" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

xcodebuild -quiet archive \
    -project "${project_path}" \
    -scheme Sfiora \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "${simulator_archive}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MARKETING_VERSION="${sfiora_version}" \
    ONLY_ACTIVE_ARCH=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

device_framework="${device_archive}/Products/Library/Frameworks/Sfiora.framework"
simulator_framework="${simulator_archive}/Products/Library/Frameworks/Sfiora.framework"
device_dsym="${device_archive}/dSYMs/Sfiora.framework.dSYM"
simulator_dsym="${simulator_archive}/dSYMs/Sfiora.framework.dSYM"
for framework_path in "${device_framework}" "${simulator_framework}"; do
    if [[ ! -d "${framework_path}" ]]; then
        echo "Archive did not contain Sfiora.framework: ${framework_path}" >&2
        exit 1
    fi
    cp "${sfiora_root}/LICENSE" "${framework_path}/LICENSE"
done
for dsym_path in "${device_dsym}" "${simulator_dsym}"; do
    if [[ ! -d "${dsym_path}" ]]; then
        echo "Archive did not contain Sfiora framework symbols: ${dsym_path}" >&2
        exit 1
    fi
done

xcodebuild -create-xcframework \
    -framework "${device_framework}" \
    -debug-symbols "${device_dsym}" \
    -framework "${simulator_framework}" \
    -debug-symbols "${simulator_dsym}" \
    -output "${xcframework_path}"

mkdir -p "${artifact_dir}"
rm -f "${artifact_path}" "${artifact_path}.sha256"
xattr -cr "${xcframework_path}"
(
    cd "${temporary_dir}"
    find Sfiora.xcframework -print \
        | LC_ALL=C sort \
        | zip -q -X -y "${artifact_path}" -@
)
sfiora_write_checksum "${artifact_path}"

printf '%s\n' "${artifact_path}"
