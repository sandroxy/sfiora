#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

skip_package=1
for argument in "$@"; do
    case "${argument}" in
        --skip-package) skip_package=1 ;;
        *)
            echo "Usage: $0 [--skip-package]" >&2
            exit 1
            ;;
    esac
done

for command_name in ditto dwarfdump lipo otool plutil unzip xcodebuild xcrun; do
    sfiora_require_command "${command_name}"
done



artifact_path="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
sfiora_verify_checksum "${artifact_path}"
bash "${script_dir}/verify-ios-xcframework-provenance.sh" "${artifact_path}"     "${sfiora_version}" "$(ruby "${script_dir}/native-input-digest.rb")" >/dev/null
archive_listing="$(unzip -Z1 "${artifact_path}")"
if grep -Eq '(^|/)__MACOSX(/|$)|(^|/)\._' <<<"${archive_listing}"; then
    echo "XCFramework archive contains macOS metadata entries." >&2
    exit 1
fi

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-ios-verify.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
ditto -x -k "${artifact_path}" "${temporary_dir}"
xcframework_path="${temporary_dir}/Sfiora.xcframework"
if [[ ! -d "${xcframework_path}" ]]; then
    echo "XCFramework archive does not contain Sfiora.xcframework." >&2
    exit 1
fi

plutil -lint "${xcframework_path}/Info.plist" >/dev/null
xcframework_json="${temporary_dir}/xcframework.json"
plutil -convert json -o "${xcframework_json}" "${xcframework_path}/Info.plist"
ruby -rjson -e '
    metadata = JSON.parse(File.read(ARGV.fetch(0)))
    libraries = metadata.fetch("AvailableLibraries")
    abort("Sfiora XCFramework must contain exactly two libraries") unless libraries.length == 2
    device = libraries.find { |library| library["SupportedPlatformVariant"].nil? }
    simulator = libraries.find { |library| library["SupportedPlatformVariant"] == "simulator" }
    abort("Sfiora XCFramework device slice is missing") unless
      device && device["SupportedPlatform"] == "ios" &&
      device.fetch("SupportedArchitectures").sort == ["arm64"] &&
      device["LibraryPath"] == "Sfiora.framework"
    abort("Sfiora XCFramework simulator slice is incomplete") unless
      simulator && simulator["SupportedPlatform"] == "ios" &&
      simulator.fetch("SupportedArchitectures").sort == ["arm64", "x86_64"] &&
      simulator["LibraryPath"] == "Sfiora.framework"
  ' "${xcframework_json}"

framework_count=0
dsym_count=0
device_framework=""
simulator_framework=""
while IFS= read -r framework_path; do
    framework_count=$((framework_count + 1))
    framework_info="${framework_path}/Info.plist"
    framework_binary="${framework_path}/Sfiora"
    plutil -lint "${framework_info}" >/dev/null

    bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${framework_info}")"
    framework_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${framework_info}")"
    minimum_version="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "${framework_info}")"
    if [[ "${bundle_identifier}" != "com.sandrox.sfiora" ]] \
        || [[ "${framework_version}" != "${sfiora_version}" ]] \
        || [[ "${minimum_version}" != "${sfiora_ios_minimum}" ]]; then
        echo "Unexpected framework metadata: ${framework_path}" >&2
        exit 1
    fi
    if [[ ! -f "${framework_binary}" ]] || [[ ! -f "${framework_path}/LICENSE" ]]; then
        echo "Framework binary or license is missing: ${framework_path}" >&2
        exit 1
    fi
    cmp "${sfiora_root}/LICENSE" "${framework_path}/LICENSE"
    if [[ ! -f "${framework_path}/Modules/Sfiora.swiftmodule/arm64-apple-ios.swiftinterface" ]] \
        && [[ ! -f "${framework_path}/Modules/Sfiora.swiftmodule/arm64-apple-ios-simulator.swiftinterface" ]]; then
        echo "Public Swift module interface is missing: ${framework_path}" >&2
        exit 1
    fi
    if ! otool -D "${framework_binary}" | grep -Fq '@rpath/Sfiora.framework/Sfiora'; then
        echo "Sfiora framework has a non-relocatable install name: ${framework_path}" >&2
        exit 1
    fi

    architectures="$(lipo -archs "${framework_binary}")"
    case "${framework_path}" in
        *simulator*)
            simulator_framework="${framework_path}"
            if [[ " ${architectures} " != *" arm64 "* ]] \
                || [[ " ${architectures} " != *" x86_64 "* ]]; then
                echo "Simulator framework must contain arm64 and x86_64." >&2
                exit 1
            fi
            ;;
        *)
            device_framework="${framework_path}"
            if [[ "${architectures}" != "arm64" ]]; then
                echo "Device framework must contain only arm64." >&2
                exit 1
            fi
            ;;
    esac
done < <(find "${xcframework_path}" -type d -name Sfiora.framework | LC_ALL=C sort)

while IFS= read -r dsym_path; do
    dsym_count=$((dsym_count + 1))
    slice_directory="$(dirname "$(dirname "${dsym_path}")")"
    framework_binary="${slice_directory}/Sfiora.framework/Sfiora"
    dsym_binary="${dsym_path}/Contents/Resources/DWARF/Sfiora"
    if [[ ! -f "${framework_binary}" || ! -f "${dsym_binary}" ]]; then
        echo "Sfiora dSYM is detached from its framework slice: ${dsym_path}" >&2
        exit 1
    fi
    framework_uuids="$(dwarfdump --uuid "${framework_binary}" | awk '{ print $2 }' | LC_ALL=C sort)"
    dsym_uuids="$(dwarfdump --uuid "${dsym_binary}" | awk '{ print $2 }' | LC_ALL=C sort)"
    if [[ -z "${framework_uuids}" || "${framework_uuids}" != "${dsym_uuids}" ]]; then
        echo "Sfiora framework and dSYM UUIDs differ: ${dsym_path}" >&2
        exit 1
    fi
done < <(find "${xcframework_path}" -type d -name Sfiora.framework.dSYM | LC_ALL=C sort)

if [[ ${framework_count} -ne 2 ]] \
    || [[ ${dsym_count} -ne 2 ]] \
    || [[ -z "${device_framework}" ]] \
    || [[ -z "${simulator_framework}" ]]; then
    echo "Sfiora XCFramework slice layout is invalid." >&2
    exit 1
fi

consumer_source="${temporary_dir}/Consumer.swift"
cp "${script_dir}/fixtures/ios-core-adapter-api.swift" "${consumer_source}"

device_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphoneos swiftc -warnings-as-errors -emit-executable \
    -target "arm64-apple-ios${sfiora_ios_minimum}" \
    -sdk "${device_sdk}" \
    -F "$(dirname "${device_framework}")" \
    -framework Sfiora \
    "${consumer_source}" \
    -o "${temporary_dir}/SfioraDeviceConsumer"
xcrun --sdk iphonesimulator swiftc -warnings-as-errors -emit-executable \
    -target "arm64-apple-ios${sfiora_ios_minimum}-simulator" \
    -sdk "${simulator_sdk}" \
    -F "$(dirname "${simulator_framework}")" \
    -framework Sfiora \
    "${consumer_source}" \
    -o "${temporary_dir}/SfioraSimulatorConsumer"

printf '%s\n' "Verified iOS artifact for Sfiora ${sfiora_version}."
