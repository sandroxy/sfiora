#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

for command_name in \
    cmp diff ditto file jar javap lipo node nm plutil ruby strings \
    unzip zipinfo xcrun; do
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

archive_path="${sfiora_root}/dist/uniapp/sfiora-uniapp-${sfiora_version}.zip"
sfiora_verify_checksum "${archive_path}"
unzip -tq "${archive_path}" >/dev/null

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-uniapp-verify.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
entry_list="${temporary_dir}/archive-entries.txt"
zipinfo -1 "${archive_path}" > "${entry_list}"

ruby -e '
  entries_path, package_id = ARGV
  entries = File.readlines(entries_path, chomp: true)
  abort("UniApp archive is empty") if entries.empty?
  abort("UniApp archive contains duplicate entries") unless
    entries.uniq.length == entries.length
  invalid = entries.find do |entry|
    entry.empty? || entry.start_with?("/") || entry.include?("\\") ||
      entry.split("/").include?("..") || !entry.start_with?("#{package_id}/")
  end
  abort("Unsafe UniApp archive entry: #{invalid}") if invalid
  required = [
    "#{package_id}/package.json",
    "#{package_id}/android/SfioraUniApp.aar",
    "#{package_id}/ios/SfioraUniApp.framework/SfioraUniApp",
    "#{package_id}/ios/Sfiora.framework/Sfiora",
    "#{package_id}/js_sdk/index.js"
  ]
  missing = required.reject { |entry| entries.include?(entry) }
  abort("UniApp archive is missing: #{missing.join(", ")}") unless missing.empty?
' "${entry_list}" "${sfiora_uniapp_id}"

ditto -x -k "${archive_path}" "${temporary_dir}/artifact"
package_root="${temporary_dir}/artifact/${sfiora_uniapp_id}"
if [[ ! -d "${package_root}" ]]; then
    echo "UniApp package root is missing: ${package_root}" >&2
    exit 1
fi

unexpected_symlink="$(find "${package_root}" -type l -print -quit)"
if [[ -n "${unexpected_symlink}" ]]; then
    echo "UniApp package contains a symbolic link: ${unexpected_symlink}" >&2
    exit 1
fi
forbidden_entry="$(
    find "${package_root}" \
        \( -name .DS_Store -o -name __MACOSX -o -name .git \
        -o -name .gradle -o -name .build -o -name build \
        -o -name DerivedData -o -name Project -o -name node_modules \
        -o -name '*.swiftsourceinfo' -o -name '*.dSYM' \
        -o -name '*.xcodeproj' -o -name '*.xcworkspace' \
        -o -name '*.gradle' -o -name '*.java' -o -name '*.kt' \
        -o -name '*.kts' -o -name '*.swift' -o -name '*.m' \
        -o -name '*.mm' -o -name '*.c' -o -name '*.cc' \
        -o -name '*.cpp' \) -print -quit
)"
if [[ -n "${forbidden_entry}" ]]; then
    echo "UniApp package contains local, generated, or source state: ${forbidden_entry}" >&2
    exit 1
fi

cmp "${package_root}/README.md" "${sfiora_root}/adapters/uniapp/README.md"
cmp "${package_root}/CHANGELOG.md" "${sfiora_root}/CHANGELOG.md"
cmp "${package_root}/LICENSE" "${sfiora_root}/LICENSE"
cmp "${package_root}/js_sdk/index.js" "${sfiora_root}/adapters/uniapp/index.js"
cmp "${package_root}/contract/types.d.ts" "${sfiora_root}/contract/types.ts"
if grep -Fq 'module.exports' "${package_root}/js_sdk/index.js"; then
    echo "UniApp wrapper must be a statically analyzable ES module." >&2
    exit 1
fi
cmp "${package_root}/js_sdk/bridge.js" "${sfiora_root}/adapters/uniapp/bridge.js"
if ! grep -Fq "../contract/types" "${package_root}/js_sdk/index.d.ts" \
    || grep -Fq "../../contract/types" "${package_root}/js_sdk/index.d.ts"; then
    echo "UniApp declaration package has an invalid contract import." >&2
    exit 1
fi

ruby -rjson -e '
  manifest_path, version, package_id, module_name, android_min, ios_min = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  abort("UniApp package name is invalid") unless manifest.fetch("name") == "Sfiora"
  abort("UniApp package id is invalid") unless manifest.fetch("id") == package_id
  abort("UniApp package version is invalid") unless manifest.fetch("version") == version
  abort("UniApp package type is invalid") unless manifest.fetch("_dp_type") == "nativeplugin"
  native = manifest.fetch("_dp_nativeplugin")
  android = native.fetch("android")
  android_plugin = android.fetch("plugins")
  abort("UniApp Android module metadata is invalid") unless android_plugin == [{
    "type" => "module",
    "name" => module_name,
    "class" => "com.sandrox.sfiora.uniapp.SfioraUniModule"
  }]
  abort("UniApp Android integration type is invalid") unless
    android.fetch("integrateType") == "aar"
  abort("UniApp Android minimum SDK is invalid") unless
    android.fetch("minSdkVersion") == android_min
  ios = native.fetch("ios")
  ios_plugin = ios.fetch("plugins")
  abort("UniApp iOS module metadata is invalid") unless ios_plugin == [{
    "type" => "module",
    "name" => module_name,
    "class" => "SfioraUniModule"
  }]
  abort("UniApp iOS integration type is invalid") unless
    ios.fetch("integrateType") == "framework"
  abort("UniApp iOS deployment target is invalid") unless
    ios.fetch("deploymentTarget") == ios_min
  abort("UniApp iOS frameworks are invalid") unless ios.fetch("frameworks") == [
    "SfioraUniApp.framework", "Sfiora.framework", "CoreNFC.framework"
  ]
  abort("UniApp embedded frameworks are invalid") unless
    ios.fetch("embedFrameworks") == ["Sfiora.framework"]
  abort("UniApp iOS architectures are invalid") unless
    ios.fetch("validArchitectures") == ["arm64"]
' "${package_root}/package.json" \
    "${sfiora_version}" \
    "${sfiora_uniapp_id}" \
    "${sfiora_uniapp_module}" \
    "${sfiora_android_min_sdk}" \
    "${sfiora_ios_minimum}"

core_aar="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
ui_aar="${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
bridge_aar="${sfiora_root}/adapters/shared/android/build/outputs/aar/sfiora-bridge-support-release.aar"
uniapp_aar="${sfiora_root}/adapters/uniapp/android/build/outputs/aar/sfiora-uniapp-release.aar"
ios_archive="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
packaged_core="${package_root}/android/Sfiora-${sfiora_version}.aar"
packaged_ui="${package_root}/android/SfioraUI-${sfiora_version}.aar"
packaged_bridge="${package_root}/android/SfioraBridgeSupport.aar"
packaged_uniapp="${package_root}/android/SfioraUniApp.aar"

cmp "${packaged_core}" "${core_aar}"
cmp "${packaged_ui}" "${ui_aar}"
cmp "${packaged_bridge}" "${bridge_aar}"
cmp "${packaged_uniapp}" "${uniapp_aar}"

ruby -rjson -rdigest -e '
  manifest_path, version, core, ui, bridge, adapter, ios = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  abort("Invalid artifact provenance schema") unless
    manifest.fetch("schemaVersion") == 1 && manifest.fetch("version") == version
  checksum = ->(path) { Digest::SHA256.file(path).hexdigest }
  expected_android = {
    "sfiora.aar" => checksum.call(core),
    "sfiora-ui.aar" => checksum.call(ui),
    "sfiora-bridge-support.aar" => checksum.call(bridge),
    "sfiora-uniapp.aar" => checksum.call(adapter)
  }
  expected_ios = {"sfiora.xcframework.zip" => checksum.call(ios)}
  native = manifest.fetch("nativeArtifacts")
  abort("Android artifact provenance mismatch") unless
    native.fetch("android") == expected_android
  abort("iOS artifact provenance mismatch") unless
    native.fetch("ios") == expected_ios
' "${package_root}/sfiora-artifacts.json" \
    "${sfiora_version}" \
    "${core_aar}" \
    "${ui_aar}" \
    "${bridge_aar}" \
    "${uniapp_aar}" \
    "${ios_archive}"

candidate_root="${temporary_dir}/candidate-ios"
mkdir -p "${candidate_root}"
ditto -x -k "${ios_archive}" "${candidate_root}"
if ! diff -qr \
    "${candidate_root}/Sfiora.xcframework/ios-arm64/Sfiora.framework" \
    "${package_root}/ios/Sfiora.framework" >/dev/null; then
    echo "Packaged UniApp iOS core differs from the native candidate." >&2
    exit 1
fi
if ! diff -qr \
    "${sfiora_root}/adapters/uniapp/ios/build/Products/SfioraUniApp.framework" \
    "${package_root}/ios/SfioraUniApp.framework" >/dev/null; then
    echo "Packaged UniApp iOS adapter differs from the verified build output." >&2
    exit 1
fi

classes_dir="${temporary_dir}/classes"
mkdir -p "${classes_dir}"
for artifact_name in core ui bridge uniapp; do
    case "${artifact_name}" in
        core) artifact="${packaged_core}" ;;
        ui) artifact="${packaged_ui}" ;;
        bridge) artifact="${packaged_bridge}" ;;
        uniapp) artifact="${packaged_uniapp}" ;;
    esac
    unzip -tq "${artifact}" >/dev/null
    unzip -p "${artifact}" classes.jar > "${classes_dir}/${artifact_name}.jar"
done
unzip -p "${dcloud_android_aar}" classes.jar > "${classes_dir}/dcloud.jar"

duplicate_classes="${temporary_dir}/duplicate-classes.txt"
for classes_jar in \
    "${classes_dir}/core.jar" \
    "${classes_dir}/ui.jar" \
    "${classes_dir}/bridge.jar" \
    "${classes_dir}/uniapp.jar"; do
    jar tf "${classes_jar}" | grep '\.class$'
done | LC_ALL=C sort | uniq -d > "${duplicate_classes}"
if [[ -s "${duplicate_classes}" ]]; then
    echo "UniApp Android artifacts contain duplicate classes:" >&2
    cat "${duplicate_classes}" >&2
    exit 1
fi

uniapp_class_list="${temporary_dir}/uniapp-classes.txt"
jar tf "${classes_dir}/uniapp.jar" > "${uniapp_class_list}"
if ! grep -Fxq \
    "com/sandrox/sfiora/uniapp/SfioraUniModule.class" \
    "${uniapp_class_list}"; then
    echo "UniApp Android adapter class is missing." >&2
    exit 1
fi
if grep -Eq '^(io/dcloud/|com/sandrox/sfiora/(core|ui|bridge)/)' \
    "${uniapp_class_list}"; then
    echo "UniApp Android adapter bundles compile-only dependencies." >&2
    exit 1
fi

android_api="${temporary_dir}/uniapp-android-api.txt"
javap -public \
    -classpath "${classes_dir}/uniapp.jar:${classes_dir}/dcloud.jar" \
    com.sandrox.sfiora.uniapp.SfioraUniModule > "${android_api}"
for method_name in \
    getCapabilities startScan cancelScan isScanning \
    writeNdef initializeNdef cancelWrite isWriting; do
    if ! grep -Fq " ${method_name}(" "${android_api}"; then
        echo "UniApp Android module is missing ${method_name}." >&2
        exit 1
    fi
done

android_log="${temporary_dir}/android-consumer.log"
if ! "${sfiora_root}/native/android/gradlew" \
    -p "${sfiora_root}/tests/consumers/uniapp/android" \
    --no-daemon \
    -PsfioraCoreAar="${packaged_core}" \
    -PsfioraUiAar="${packaged_ui}" \
    -PsfioraBridgeAar="${packaged_bridge}" \
    -PsfioraUniAppAar="${packaged_uniapp}" \
    -PdcloudUniAppAar="${dcloud_android_aar}" \
    :app:clean :app:assembleDebug > "${android_log}" 2>&1; then
    tail -n 200 "${android_log}" >&2
    exit 1
fi

ios_dir="${package_root}/ios"
adapter_framework="${ios_dir}/SfioraUniApp.framework"
core_framework="${ios_dir}/Sfiora.framework"
for required_file in \
    "${adapter_framework}/SfioraUniApp" \
    "${adapter_framework}/Headers/SfioraUniModule.h" \
    "${adapter_framework}/Headers/SfioraUniApp-Swift.h" \
    "${adapter_framework}/Modules/module.modulemap" \
    "${core_framework}/Sfiora"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "UniApp iOS framework file is missing: ${required_file}" >&2
        exit 1
    fi
done

if [[ "$(plutil -extract CFBundleShortVersionString raw -o - \
    "${adapter_framework}/Info.plist")" != "${sfiora_version}" ]] \
    || [[ "$(plutil -extract MinimumOSVersion raw -o - \
    "${adapter_framework}/Info.plist")" != "${sfiora_ios_minimum}" ]]; then
    echo "UniApp iOS adapter metadata does not match release metadata." >&2
    exit 1
fi
if [[ "$(lipo -archs "${adapter_framework}/SfioraUniApp")" != "arm64" ]] \
    || [[ "$(lipo -archs "${core_framework}/Sfiora")" != "arm64" ]]; then
    echo "UniApp iOS frameworks must contain the arm64 device architecture only." >&2
    exit 1
fi
if ! file "${adapter_framework}/SfioraUniApp" | grep -Fq "current ar archive" \
    || ! file "${core_framework}/Sfiora" \
        | grep -Fq "dynamically linked shared library arm64"; then
    echo "UniApp iOS framework linkage types are invalid." >&2
    exit 1
fi
ios_symbols="${temporary_dir}/sfiora-uniapp-symbols.txt"
ios_strings="${temporary_dir}/sfiora-uniapp-strings.txt"
nm -gU "${adapter_framework}/SfioraUniApp" > "${ios_symbols}"
strings "${adapter_framework}/SfioraUniApp" > "${ios_strings}"
if ! grep -Fq '_OBJC_CLASS_$_SfioraUniModule' "${ios_symbols}"; then
    echo "UniApp iOS adapter does not export SfioraUniModule." >&2
    exit 1
fi
for selector in \
    'getCapabilities:' 'startScan:callback:' 'cancelScan:' 'isScanning:' \
    'writeNdef:options:callback:' \
    'initializeNdef:marker:options:callback:' \
    'cancelWrite:' 'isWriting:'; do
    if ! grep -Fq "${selector}" "${ios_strings}"; then
        echo "UniApp iOS adapter is missing selector ${selector}." >&2
        exit 1
    fi
done
adapter_string_audit="${temporary_dir}/sfiora-uniapp-framework-strings.txt"
: > "${adapter_string_audit}"
while IFS= read -r framework_file; do
    strings "${framework_file}" >> "${adapter_string_audit}"
done < <(find "${adapter_framework}" -type f -print)
if grep -Eq '/Users/|/home/|workspace/code|IntegratedPlugins' \
    "${adapter_string_audit}"; then
    echo "UniApp iOS adapter leaks a local source path." >&2
    exit 1
fi

iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun clang \
    -fmodules \
    -fsyntax-only \
    -target arm64-apple-ios"${sfiora_ios_minimum}" \
    -isysroot "${iphoneos_sdk}" \
    -fmodules-cache-path="${temporary_dir}/ClangModuleCache" \
    -F "${ios_dir}" \
    -I "${dcloud_ios_sdk_root}/SDK/inc/DCUni" \
    -I "${dcloud_ios_sdk_root}/SDK/inc/weexHeader" \
    "${sfiora_root}/tests/consumers/uniapp/ios/ImportProbe.m"
node --test "${sfiora_root}/tests/js/bridge-wrappers.test.mjs"
printf '%s\n' "UniApp nativeplugin artifact verification passed for Android and iOS."
