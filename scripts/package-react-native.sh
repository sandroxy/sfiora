#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

for command_name in npm ruby tar unzip; do
    sfiora_require_command "${command_name}"
done

core_aar="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
ui_aar="${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
ios_archive="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
for artifact_path in "${core_aar}" "${ui_aar}" "${ios_archive}"; do
    sfiora_verify_checksum "${artifact_path}"
done

"${sfiora_root}/native/android/gradlew" \
    -p "${sfiora_root}/adapters/android" \
    --no-daemon \
    -PsfioraCoreAar="${core_aar}" \
    -PsfioraUiAar="${ui_aar}" \
    :bridge-support:clean \
    :bridge-support:assembleRelease

bridge_aar="${sfiora_root}/adapters/shared/android/build/outputs/aar/sfiora-bridge-support-release.aar"
if [[ ! -f "${bridge_aar}" ]]; then
    echo "The shared Android bridge AAR was not produced: ${bridge_aar}" >&2
    exit 1
fi

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-react-native-package.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
package_dir="${temporary_dir}/package"
source_dir="${sfiora_root}/adapters/react-native"
artifact_dir="${sfiora_root}/dist/react-native"
artifact_name="sandrox-sfiora-${sfiora_version}.tgz"
artifact_path="${artifact_dir}/${artifact_name}"

mkdir -p \
    "${package_dir}/android/libs" \
    "${package_dir}/ios/Frameworks" \
    "${package_dir}/shared/ios/Sources" \
    "${package_dir}/contract"

for file_name in \
    package.json \
    index.js \
    index.d.ts \
    app.plugin.js \
    react-native.config.js \
    tsconfig.json \
    SfioraReactNative.podspec \
    README.md; do
    cp "${source_dir}/${file_name}" "${package_dir}/${file_name}"
done
cp "${sfiora_root}/LICENSE" "${package_dir}/LICENSE"
cp "${sfiora_root}/contract/types.ts" "${package_dir}/contract/types.ts"
cp "${sfiora_root}/contract/bridge.schema.json" \
    "${package_dir}/contract/bridge.schema.json"
cp -R "${source_dir}/plugin" "${package_dir}/plugin"
cp -R "${source_dir}/src" "${package_dir}/src"
cp -R "${source_dir}/android/src" "${package_dir}/android/src"
cp "${source_dir}/android/build.gradle" "${package_dir}/android/build.gradle"
cp "${source_dir}/android/consumer-rules.pro" \
    "${package_dir}/android/consumer-rules.pro"
cp -R "${source_dir}/ios/." "${package_dir}/ios"
cp -R "${sfiora_root}/adapters/shared/ios/Sources/SfioraBridgeSupport" \
    "${package_dir}/shared/ios/Sources/SfioraBridgeSupport"

cp "${core_aar}" "${package_dir}/android/libs/sfiora.aar"
cp "${ui_aar}" "${package_dir}/android/libs/sfiora-ui.aar"
cp "${bridge_aar}" \
    "${package_dir}/android/libs/sfiora-bridge-support.aar"
unzip -q "${ios_archive}" -d "${package_dir}/ios/Frameworks"

ruby -rjson -rdigest -e '
  output, version, core, ui, bridge, ios = ARGV
  checksum = ->(path) { Digest::SHA256.file(path).hexdigest }
  manifest = {
    "schemaVersion" => 1,
    "version" => version,
    "nativeArtifacts" => {
      "android" => {
        "sfiora.aar" => checksum.call(core),
        "sfiora-ui.aar" => checksum.call(ui),
        "sfiora-bridge-support.aar" => checksum.call(bridge)
      },
      "ios" => {
        "sfiora.xcframework.zip" => checksum.call(ios)
      }
    }
  }
  File.write(output, JSON.pretty_generate(manifest) + "\n")
' "${package_dir}/sfiora-artifacts.json" \
    "${sfiora_version}" \
    "${core_aar}" \
    "${ui_aar}" \
    "${bridge_aar}" \
    "${ios_archive}"

ruby -rjson -e '
  package_path, expected_name, expected_version = ARGV
  package = JSON.parse(File.read(package_path))
  abort("React Native package name differs from plugin.json") unless
    package.fetch("name") == expected_name
  abort("React Native package version differs from plugin.json") unless
    package.fetch("version") == expected_version
' "${package_dir}/package.json" \
    "${sfiora_react_native_package}" \
    "${sfiora_version}"

mkdir -p "${artifact_dir}"
rm -f -- "${artifact_path}" "${artifact_path}.sha256"
npm pack \
    --ignore-scripts \
    --pack-destination "${artifact_dir}" \
    "${package_dir}" >/dev/null

if [[ ! -f "${artifact_path}" ]]; then
    echo "React Native package was not produced: ${artifact_path}" >&2
    exit 1
fi
if tar -tzf "${artifact_path}" \
    | grep -E '(^|/)(build|\.gradle|\.build|DerivedData|node_modules)(/|$)' \
    >/dev/null; then
    echo "React Native package contains generated or local state." >&2
    exit 1
fi

sfiora_write_checksum "${artifact_path}"
printf '%s\n' "${artifact_path}"
