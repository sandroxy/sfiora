#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sfiora_root="$(cd "${script_dir}/../../.." && pwd)"
source "${sfiora_root}/scripts/release-common.sh"

for command_name in ditto strings xcodebuild xcrun; do
    sfiora_require_command "${command_name}"
done

dcloud_sdk_root="${DCLOUD_IOS_SDK_ROOT:-}"
core_archive="${SFIORA_IOS_XCFRAMEWORK_ZIP:-${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip}"
if [[ -z "${dcloud_sdk_root}" \
    || ! -f "${dcloud_sdk_root}/SDK/inc/DCUni/DCUniModule.h" ]]; then
    echo "Set DCLOUD_IOS_SDK_ROOT to the DCloud iOS offline SDK root." >&2
    exit 1
fi
if [[ ! -f "${core_archive}" ]]; then
    echo "Sfiora iOS candidate is missing: ${core_archive}" >&2
    exit 1
fi

build_root="${script_dir}/build"
artifact_root="${build_root}/CoreArtifact"
derived_data="${build_root}/DerivedData"
output_root="${build_root}/Products"
core_slice="${artifact_root}/Sfiora.xcframework/ios-arm64"
adapter_framework="${derived_data}/Build/Products/Release-iphoneos/SfioraUniApp.framework"

rm -rf -- "${build_root}"
mkdir -p "${artifact_root}"
ditto -x -k "${core_archive}" "${artifact_root}"
if [[ ! -d "${core_slice}/Sfiora.framework" ]]; then
    echo "The device Sfiora.framework is missing from ${core_archive}." >&2
    exit 1
fi

xcodebuild \
    -quiet \
    -project "${script_dir}/SfioraUniApp.xcodeproj" \
    -scheme SfioraUniApp \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${derived_data}" \
    DCLOUD_IOS_SDK_ROOT="${dcloud_sdk_root}" \
    SFIORA_FRAMEWORKS_DIR="${core_slice}" \
    MARKETING_VERSION="${sfiora_version}" \
    OTHER_CFLAGS="-fdebug-prefix-map=${sfiora_root}=." \
    OTHER_SWIFT_FLAGS="-debug-prefix-map ${sfiora_root}=." \
    SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    clean build

if [[ ! -d "${adapter_framework}" ]]; then
    echo "The UniApp adapter framework was not produced: ${adapter_framework}" >&2
    exit 1
fi

rm -rf -- "${adapter_framework}/Modules/SfioraUniApp.swiftmodule"
find "${adapter_framework}" -name '*.swiftsourceinfo' -delete
xcrun strip -S "${adapter_framework}/SfioraUniApp"
string_audit="${build_root}/SfioraUniApp.strings"
: > "${string_audit}"
while IFS= read -r framework_file; do
    strings "${framework_file}" >> "${string_audit}"
done < <(find "${adapter_framework}" -type f -print)
if grep -Fq "${sfiora_root}" "${string_audit}"; then
    echo "The UniApp adapter contains a local source path." >&2
    exit 1
fi
rm -f -- "${string_audit}"

mkdir -p "${output_root}"
rm -rf -- \
    "${output_root}/SfioraUniApp.framework" \
    "${output_root}/Sfiora.framework"
ditto "${adapter_framework}" "${output_root}/SfioraUniApp.framework"
ditto "${core_slice}/Sfiora.framework" "${output_root}/Sfiora.framework"

printf '%s\n' "${output_root}"
