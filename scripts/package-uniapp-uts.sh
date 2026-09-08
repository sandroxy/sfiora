#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
sfiora_parse_package_arguments "$@"
archive_path="${sfiora_root}/dist/uniapp/sfiora-uniapp-uts-${sfiora_version}.zip"
sfiora_guard_output "${archive_path}"
bash "${script_dir}/sync-uniapp-js.sh" --check
core_aar="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
ui_aar="${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
ios_archive="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
for artifact in "${core_aar}" "${ui_aar}" "${ios_archive}"; do
    sfiora_verify_checksum "${artifact}"
done
"${sfiora_root}/native/android/gradlew" -p "${sfiora_root}/adapters/android" --no-daemon \
    -PsfioraCoreAar="${core_aar}" -PsfioraUiAar="${ui_aar}" \
    :bridge-support:clean :bridge-support:assembleRelease
"${sfiora_root}/adapters/uniapp/ios/build-runtime-framework.sh" >/dev/null
temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-uts-package.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
package_root="${temporary_dir}/${sfiora_uniapp_id}"
mkdir -p "${package_root}"
while IFS= read -r -d '' relative; do
    destination="${package_root}/${relative#uni_modules/${sfiora_uniapp_id}/}"
    mkdir -p "$(dirname "${destination}")"
    cp "${sfiora_root}/${relative}" "${destination}"
done < <(git -C "${sfiora_root}" ls-files -cz --others --exclude-standard -- "uni_modules/${sfiora_uniapp_id}")
cp "${sfiora_root}/adapters/uniapp/README.md" "${package_root}/readme.md"
cp "${sfiora_root}/CHANGELOG.md" "${package_root}/changelog.md"
android_libs="${package_root}/utssdk/app-android/libs"
ios_frameworks="${package_root}/utssdk/app-ios/Frameworks"
mkdir -p "${android_libs}" "${ios_frameworks}" "${package_root}/contract"
bridge_aar="${sfiora_root}/adapters/shared/android/build/outputs/aar/sfiora-bridge-support-release.aar"
cp "${core_aar}" "${android_libs}/sfiora.aar"
cp "${ui_aar}" "${android_libs}/sfiora-ui.aar"
cp "${bridge_aar}" "${android_libs}/sfiora-bridge-support.aar"
ditto "${sfiora_root}/adapters/uniapp/ios/build-runtime/Products/SfioraUniRuntime.framework" \
    "${ios_frameworks}/SfioraUniRuntime.framework"
ditto "${sfiora_root}/adapters/uniapp/ios/build-runtime/Products/Sfiora.framework" \
    "${ios_frameworks}/Sfiora.framework"
cp "${sfiora_root}/contract/types.ts" "${package_root}/contract/types.d.ts"
cp "${sfiora_root}/contract/bridge.schema.json" "${package_root}/contract/bridge.schema.json"
ruby -e 'File.write(ARGV[1], File.read(ARGV[0]).gsub(%q{../../contract/types}, %q{../contract/types}))' \
    "${sfiora_root}/adapters/uniapp/index.d.ts" "${package_root}/js_sdk/index.d.ts"
ruby -rjson -rdigest -e '
  output, version, core, ui, bridge, ios = ARGV
  sha = ->(path) { Digest::SHA256.file(path).hexdigest }
  File.write(output, JSON.pretty_generate({
    schemaVersion: 1, version: version,
    nativeArtifacts: {
      android: {"sfiora.aar" => sha.call(core), "sfiora-ui.aar" => sha.call(ui),
        "sfiora-bridge-support.aar" => sha.call(bridge)},
      ios: {"sfiora.xcframework.zip" => sha.call(ios)}
    }
  }) + "\n")
' "${package_root}/sfiora-artifacts.json" "${sfiora_version}" \
    "${core_aar}" "${ui_aar}" "${bridge_aar}" "${ios_archive}"
mkdir -p "$(dirname "${archive_path}")"
staged_archive="${temporary_dir}/package.zip"
(
    cd "${package_root}"
    find . -type f -print | LC_ALL=C sort | zip -q -X "${staged_archive}" -@
)
mv -f "${staged_archive}" "${archive_path}"
sfiora_write_checksum "${archive_path}"
printf '%s\n' "${archive_path}"
