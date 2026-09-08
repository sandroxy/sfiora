#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

for command_name in node npm pod ruby tar xcodebuild; do
    sfiora_require_command "${command_name}"
done

react_native_path="${SFIORA_REACT_NATIVE_PATH:-}"
react_native_gradle_plugin_path="${SFIORA_REACT_NATIVE_GRADLE_PLUGIN_PATH:-}"
react_native_codegen_path="${SFIORA_REACT_NATIVE_CODEGEN_PATH:-}"
for required_path in \
    "${react_native_path}/package.json" \
    "${react_native_gradle_plugin_path}/package.json" \
    "${react_native_codegen_path}/package.json"; do
    if [[ ! -f "${required_path}" ]]; then
        echo "Set the SFIORA_REACT_NATIVE_PATH, SFIORA_REACT_NATIVE_GRADLE_PLUGIN_PATH, and SFIORA_REACT_NATIVE_CODEGEN_PATH environment variables." >&2
        exit 1
    fi
done
react_native_path="$(cd "${react_native_path}" && pwd -P)"
react_native_gradle_plugin_path="$(cd "${react_native_gradle_plugin_path}" && pwd -P)"
react_native_codegen_path="$(cd "${react_native_codegen_path}" && pwd -P)"
react_native_version="$(node -p "require('${react_native_path}/package.json').version")"

artifact_path="${sfiora_root}/dist/react-native/sandrox-sfiora-${sfiora_version}.tgz"
sfiora_verify_checksum "${artifact_path}"

temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-react-native-verify.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
package_dir="${temporary_dir}/package"
consumer_dir="${temporary_dir}/consumer"
mkdir -p "${package_dir}" "${consumer_dir}"
tar -xzf "${artifact_path}" --strip-components 1 -C "${package_dir}"
cp -R "${sfiora_root}/tests/consumers/react-native/." "${consumer_dir}"

if find "${package_dir}" \
    \( -name .DS_Store -o -name .gradle -o -name .build \
    -o -name DerivedData -o -name node_modules \) \
    -print -quit | grep -q .; then
    echo "React Native package contains generated or local state." >&2
    exit 1
fi

(
    cd "${consumer_dir}"
    npm install \
        --ignore-scripts \
        --legacy-peer-deps \
        --no-package-lock \
        "${artifact_path}" >/dev/null
    mkdir -p node_modules/react-native
    cp -R react-native-stub/. node_modules/react-native
    node verify.cjs
)

installed_package="${consumer_dir}/node_modules/@sandrox/sfiora"
if ! diff -qr "${package_dir}" "${installed_package}" >/dev/null; then
    echo "Installed React Native package differs from the release archive." >&2
    exit 1
fi
pod ipc spec "${package_dir}/SfioraReactNative.podspec" >/dev/null

for architecture in false true; do
    "${sfiora_root}/native/android/gradlew" \
        -p "${consumer_dir}/android" \
        --no-daemon \
        -PnewArchEnabled="${architecture}" \
        -PsfioraReactNativeVersion="${react_native_version}" \
        -PsfioraReactNativePath="${react_native_path}" \
        -PsfioraReactNativeGradlePluginPath="${react_native_gradle_plugin_path}" \
        -PsfioraReactNativeCodegenPath="${react_native_codegen_path}" \
        -PreactNativeGradlePluginPath="${react_native_gradle_plugin_path}" \
        -PsfioraPackagePath="${package_dir}" \
        :app:compileDebugJavaWithJavac
done

if ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    ruby "${consumer_dir}/ios/create-project.rb"
else
    xcodeproj_executable="$(command -v xcodeproj || true)"
    if [[ -z "${xcodeproj_executable}" ]]; then
        echo "The CocoaPods xcodeproj executable is required." >&2
        exit 1
    fi
    resolved_xcodeproj_executable="$(
        ruby -e 'puts File.realpath(ARGV.fetch(0))' "${xcodeproj_executable}"
    )"
    cocoapods_installation_root="$(
        cd "$(dirname "${resolved_xcodeproj_executable}")/.." && pwd
    )"
    cocoapods_gem_home="${cocoapods_installation_root}/libexec"
    if [[ ! -d "${cocoapods_gem_home}/gems" ]]; then
        echo "Unable to locate the CocoaPods Ruby environment." >&2
        exit 1
    fi
    GEM_HOME="${cocoapods_gem_home}" \
        ruby "${consumer_dir}/ios/create-project.rb"
fi

install_pods() {
    local architecture="$1"
    local log_path="$2"
    if ! (
        cd "${consumer_dir}/ios"
        SFIORA_REACT_NATIVE_PATH="${react_native_path}" \
            SFIORA_PACKAGE_PATH="${package_dir}" \
            RCT_NEW_ARCH_ENABLED="${architecture}" \
            pod install >"${log_path}" 2>&1
    ); then
        tail -n 200 "${log_path}" >&2
        exit 1
    fi
}

install_pods 0 "${temporary_dir}/pod-install-legacy.log"
legacy_log="${temporary_dir}/xcodebuild-legacy.log"
if ! xcodebuild \
    -workspace "${consumer_dir}/ios/SfioraConsumer.xcworkspace" \
    -scheme SfioraConsumer \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${temporary_dir}/DerivedDataLegacy" \
    CODE_SIGNING_ALLOWED=NO \
    build >"${legacy_log}" 2>&1; then
    tail -n 200 "${legacy_log}" >&2
    exit 1
fi
legacy_simulator_log="${temporary_dir}/xcodebuild-legacy-simulator.log"
if ! xcodebuild \
    -workspace "${consumer_dir}/ios/SfioraConsumer.xcworkspace" \
    -scheme SfioraConsumer \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${temporary_dir}/DerivedDataLegacySimulator" \
    CODE_SIGNING_ALLOWED=NO \
    build >"${legacy_simulator_log}" 2>&1; then
    tail -n 200 "${legacy_simulator_log}" >&2
    exit 1
fi

install_pods 1 "${temporary_dir}/pod-install-new-architecture.log"
new_arch_log="${temporary_dir}/xcodebuild-new-architecture.log"
if ! xcodebuild \
    -workspace "${consumer_dir}/ios/SfioraConsumer.xcworkspace" \
    -scheme SfioraReactNative \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${temporary_dir}/DerivedDataNewArchitecture" \
    CODE_SIGNING_ALLOWED=NO \
    build >"${new_arch_log}" 2>&1; then
    tail -n 200 "${new_arch_log}" >&2
    exit 1
fi
new_arch_simulator_log="${temporary_dir}/xcodebuild-new-architecture-simulator.log"
if ! xcodebuild \
    -workspace "${consumer_dir}/ios/SfioraConsumer.xcworkspace" \
    -scheme SfioraReactNative \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${temporary_dir}/DerivedDataNewArchitectureSimulator" \
    CODE_SIGNING_ALLOWED=NO \
    build >"${new_arch_simulator_log}" 2>&1; then
    tail -n 200 "${new_arch_simulator_log}" >&2
    exit 1
fi

node --test "${sfiora_root}/tests/js/bridge-wrappers.test.mjs"
printf '%s\n' "React Native artifact verification passed for legacy and new architectures on iOS devices and simulators."
