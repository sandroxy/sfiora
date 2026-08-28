#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

for command_name in plutil xattr xcodebuild zip; do
    sfiora_require_command "${command_name}"
done

ios_dir="${sfiora_root}/native/ios"
project_path="${ios_dir}/Sfiora.xcodeproj"
artifact_dir="${sfiora_root}/dist/native-ios"
artifact_name="sfiora-${sfiora_version}.xcframework.zip"
artifact_path="${artifact_dir}/${artifact_name}"
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
