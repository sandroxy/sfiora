#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
sfiora_parse_package_arguments "$@"
sfiora_guard_output "${sfiora_root}/dist/uniapp/sfiora-uniapp-${sfiora_version}.zip"

for command_name in ruby zip; do
    sfiora_require_command "${command_name}"
done

dcloud_android_aar="${DCLOUD_ANDROID_UNIAPP_AAR:-}"
dcloud_ios_sdk_root="${DCLOUD_IOS_SDK_ROOT:-}"
if [[ -z "${dcloud_android_aar}" || ! -f "${dcloud_android_aar}" ]]; then
    echo "Set DCLOUD_ANDROID_UNIAPP_AAR to uniapp-v8-release.aar." >&2
    exit 1
fi
if [[ -z "${dcloud_ios_sdk_root}" \
    || ! -f "${dcloud_ios_sdk_root}/SDK/inc/DCUni/DCUniModule.h" ]]; then
    echo "Set DCLOUD_IOS_SDK_ROOT to the DCloud iOS offline SDK root." >&2
    exit 1
fi

core_aar="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
ui_aar="${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
ios_archive="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
for artifact_path in "${core_aar}" "${ui_aar}" "${ios_archive}"; do
    sfiora_verify_checksum "${artifact_path}"
done

"${sfiora_root}/native/android/gradlew" \
    -p "${sfiora_root}/adapters/android" \
    --no-daemon \
    -PincludeUniAppAdapter=true \
    -PuniAppAarPath="${dcloud_android_aar}" \
    -PsfioraCoreAar="${core_aar}" \
    -PsfioraUiAar="${ui_aar}" \
    :bridge-support:clean \
    :bridge-support:assembleRelease \
    :uniapp:clean \
    :uniapp:assembleRelease

DCLOUD_IOS_SDK_ROOT="${dcloud_ios_sdk_root}" \
SFIORA_IOS_XCFRAMEWORK_ZIP="${ios_archive}" \
    "${sfiora_root}/adapters/uniapp/ios/build-framework.sh" >/dev/null

bridge_aar="${sfiora_root}/adapters/shared/android/build/outputs/aar/sfiora-bridge-support-release.aar"
uniapp_aar="${sfiora_root}/adapters/uniapp/android/build/outputs/aar/sfiora-uniapp-release.aar"
ios_products="${sfiora_root}/adapters/uniapp/ios/build/Products"
for artifact_path in \
    "${bridge_aar}" \
    "${uniapp_aar}" \
    "${ios_products}/SfioraUniApp.framework/SfioraUniApp" \
    "${ios_products}/Sfiora.framework/Sfiora"; do
    if [[ ! -e "${artifact_path}" ]]; then
        echo "UniApp build output is missing: ${artifact_path}" >&2
        exit 1
    fi
done

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-uniapp-package.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
package_root="${temporary_dir}/${sfiora_uniapp_id}"
artifact_dir="${sfiora_root}/dist/uniapp"
archive_name="sfiora-uniapp-${sfiora_version}.zip"
archive_path="${artifact_dir}/${archive_name}"

mkdir -p \
    "${package_root}/android" \
    "${package_root}/ios" \
    "${package_root}/js_sdk" \
    "${package_root}/contract"
cp "${uniapp_aar}" "${package_root}/android/SfioraUniApp.aar"
cp "${bridge_aar}" "${package_root}/android/SfioraBridgeSupport.aar"
cp "${core_aar}" "${package_root}/android/Sfiora-${sfiora_version}.aar"
cp "${ui_aar}" "${package_root}/android/SfioraUI-${sfiora_version}.aar"
cp -R "${ios_products}/SfioraUniApp.framework" "${package_root}/ios"
cp -R "${ios_products}/Sfiora.framework" "${package_root}/ios"
cp "${sfiora_root}/adapters/uniapp/index.js" \
    "${package_root}/js_sdk/index.js"
cp "${sfiora_root}/adapters/uniapp/bridge.js" "${package_root}/js_sdk/bridge.js"
cp "${sfiora_root}/contract/types.ts" \
    "${package_root}/contract/types.d.ts"
cp "${sfiora_root}/LICENSE" "${package_root}/LICENSE"
cp "${sfiora_root}/adapters/uniapp/README.md" "${package_root}/README.md"
cp "${sfiora_root}/CHANGELOG.md" "${package_root}/CHANGELOG.md"

ruby -e '
  source, destination = ARGV
  value = File.read(source).gsub(%q{'../../contract/types'}, %q{'../contract/types'})
  File.write(destination, value)
' "${sfiora_root}/adapters/uniapp/index.d.ts" \
    "${package_root}/js_sdk/index.d.ts"

ruby -rjson -e '
  template, output, version = ARGV
  value = File.read(template).gsub("@VERSION@", version)
  package = JSON.parse(value)
  abort("UniApp package version replacement failed") unless
    package.fetch("version") == version
  File.write(output, value)
' "${sfiora_root}/adapters/uniapp/packaging/package.template.json" \
    "${package_root}/package.json" \
    "${sfiora_version}"

ruby -rjson -rdigest -e '
  output, version, core, ui, bridge, adapter, ios = ARGV
  checksum = ->(path) { Digest::SHA256.file(path).hexdigest }
  manifest = {
    "schemaVersion" => 1,
    "version" => version,
    "nativeArtifacts" => {
      "android" => {
        "sfiora.aar" => checksum.call(core),
        "sfiora-ui.aar" => checksum.call(ui),
        "sfiora-bridge-support.aar" => checksum.call(bridge),
        "sfiora-uniapp.aar" => checksum.call(adapter)
      },
      "ios" => {
        "sfiora.xcframework.zip" => checksum.call(ios)
      }
    }
  }
  File.write(output, JSON.pretty_generate(manifest) + "\n")
' "${package_root}/sfiora-artifacts.json" \
    "${sfiora_version}" \
    "${core_aar}" \
    "${ui_aar}" \
    "${bridge_aar}" \
    "${uniapp_aar}" \
    "${ios_archive}"

mkdir -p "${artifact_dir}"
rm -f -- "${archive_path}" "${archive_path}.sha256"
(
    cd "${temporary_dir}"
    find "${sfiora_uniapp_id}" -print \
        | LC_ALL=C sort \
        | zip -q -X -y "${archive_path}" -@
)
sfiora_write_checksum "${archive_path}"

printf '%s\n' "${archive_path}"
