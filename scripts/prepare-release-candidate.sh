#!/usr/bin/env bash

set -euo pipefail

allow_dirty=0
allow_unsigned=0
for argument in "$@"; do
    case "${argument}" in
        --allow-dirty) allow_dirty=1 ;;
        --allow-unsigned) allow_unsigned=1 ;;
        *)
            echo "Usage: $0 [--allow-dirty] [--allow-unsigned]" >&2
            exit 1
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
for command_name in git tar unzip; do
    sfiora_require_command "${command_name}"
done

initial_commit="$(git -C "${sfiora_root}" rev-parse HEAD)"
initial_dirty=false
if [[ -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then
    initial_dirty=true
fi
if [[ ${allow_dirty} -eq 0 && "${initial_dirty}" == true ]]; then
    echo "Release candidate preparation requires a clean worktree." >&2
    echo "Use --allow-dirty only to create a non-acceptable rehearsal." >&2
    exit 1
fi

sfiora_assert_version_unpublished
"${script_dir}/verify-release-metadata.sh"

native_manifest="${sfiora_root}/dist/native-release/sfiora-native-${sfiora_version}.json"
native_checksums="${sfiora_root}/dist/native-release/sfiora-native-${sfiora_version}-SHA256SUMS"
core_aar="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
ui_aar="${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
maven_repository="${sfiora_root}/dist/native-android/sfiora-${sfiora_version}-maven.zip"
ios_framework="${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
react_native_package="${sfiora_root}/dist/react-native/sandrox-sfiora-${sfiora_version}.tgz"
uniapp_package="${sfiora_root}/dist/uniapp/sfiora-uniapp-${sfiora_version}.zip"
artifacts=(
    "${core_aar}"
    "${ui_aar}"
    "${maven_repository}"
    "${ios_framework}"
    "${react_native_package}"
    "${uniapp_package}"
)

for required_path in "${native_manifest}" "${native_checksums}"; do
    if [[ ! -f "${required_path}" ]]; then
        echo "Required native release evidence is missing: ${required_path}" >&2
        exit 1
    fi
done
for artifact_path in "${artifacts[@]}"; do
    sfiora_verify_checksum "${artifact_path}"
done

read -r native_commit native_dirty native_signed < <(ruby -rjson -rdigest -e '
  manifest_path, version, root, *files = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  abort("Unexpected native manifest schema") unless manifest.fetch("schemaVersion") == 1
  abort("Unexpected native manifest plugin") unless manifest.fetch("plugin") == "sfiora"
  abort("Unexpected native manifest version") unless manifest.fetch("version") == version
  commit = manifest.fetch("commit")
  dirty = manifest.fetch("dirty")
  signed = manifest.fetch("androidMavenSigned")
  abort("Invalid native manifest commit") unless
    commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
  abort("Invalid native manifest dirty flag") unless [true, false].include?(dirty)
  abort("Invalid native manifest signing flag") unless [true, false].include?(signed)
  indexed = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
  files.each do |file|
    relative = file.delete_prefix("#{root}/")
    entry = indexed.fetch(relative) { abort("Native manifest is missing #{relative}") }
    abort("Native manifest byte count differs for #{relative}") unless
      entry.fetch("bytes") == File.size(file)
    abort("Native manifest checksum differs for #{relative}") unless
      entry.fetch("sha256") == Digest::SHA256.file(file).hexdigest
  end
  puts [commit, dirty, signed].join(" ")
' "${native_manifest}" "${sfiora_version}" "${sfiora_root}" \
    "${core_aar}" "${ui_aar}" "${maven_repository}" "${ios_framework}")
if [[ "${native_commit}" != "${initial_commit}" ]]; then
    echo "Native artifacts came from ${native_commit}, not current commit ${initial_commit}." >&2
    exit 1
fi
if [[ ${allow_unsigned} -eq 0 && "${native_signed}" != true ]]; then
    echo "A formal candidate requires signed Android Maven artifacts." >&2
    echo "Use --allow-unsigned only to create a non-acceptable rehearsal." >&2
    exit 1
fi

react_native_metadata="$(tar -xOf "${react_native_package}" package/package.json)"
react_native_provenance="$(tar -xOf "${react_native_package}" package/sfiora-artifacts.json)"
uniapp_metadata="$(unzip -p "${uniapp_package}" "${sfiora_uniapp_id}/package.json")"
uniapp_provenance="$(unzip -p "${uniapp_package}" "${sfiora_uniapp_id}/sfiora-artifacts.json")"
ruby -rjson -rdigest -e '
  version, rn_package, rn_provenance, uni_package, uni_provenance,
    core, ui, ios = ARGV
  rn = JSON.parse(rn_package)
  abort("Unexpected React Native package identity") unless
    rn.fetch("name") == "@sandrox/sfiora" && rn.fetch("version") == version
  uni = JSON.parse(uni_package)
  abort("Unexpected UniApp package identity") unless
    uni.fetch("id") == "Sandrox-Sfiora" &&
      uni.fetch("version") == version && uni.fetch("_dp_type") == "nativeplugin"
  expected_android = {
    "sfiora.aar" => Digest::SHA256.file(core).hexdigest,
    "sfiora-ui.aar" => Digest::SHA256.file(ui).hexdigest
  }
  expected_ios = Digest::SHA256.file(ios).hexdigest
  [rn_provenance, uni_provenance].each do |raw|
    provenance = JSON.parse(raw)
    abort("Unexpected adapter provenance schema") unless
      provenance.fetch("schemaVersion") == 1 && provenance.fetch("version") == version
    android = provenance.dig("nativeArtifacts", "android")
    abort("Adapter does not embed the verified Android artifacts") unless
      expected_android.all? { |name, checksum| android.fetch(name) == checksum }
    abort("Adapter does not embed the verified iOS artifact") unless
      provenance.dig("nativeArtifacts", "ios", "sfiora.xcframework.zip") == expected_ios
  end
' "${sfiora_version}" "${react_native_metadata}" "${react_native_provenance}" \
    "${uniapp_metadata}" "${uniapp_provenance}" \
    "${core_aar}" "${ui_aar}" "${ios_framework}"

commit="$(git -C "${sfiora_root}" rev-parse HEAD)"
dirty=false
if [[ -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then
    dirty=true
fi
if [[ ${allow_dirty} -eq 0 ]] \
    && { [[ "${dirty}" == true ]] || [[ "${commit}" != "${initial_commit}" ]]; }; then
    echo "The source revision changed while preparing the release candidate." >&2
    exit 1
fi

state=candidate
output_root="${sfiora_root}/dist/candidates"
if [[ "${dirty}" == true || "${native_dirty}" == true || "${native_signed}" != true ]]; then
    state=rehearsal
    output_root="${sfiora_root}/dist/rehearsals"
fi

snapshot_arguments=(
    --plugin sfiora
    --version "${sfiora_version}"
    --repository "${sfiora_repository}"
    --commit "${commit}"
    --dirty "${dirty}"
    --root "${sfiora_root}"
    --output-root "${output_root}"
    --state "${state}"
    --qualification "androidMavenSigned=${native_signed}"
    --qualification nativeManifestVerified=true
    --qualification adapterProvenanceVerified=true
    --qualification versionUnpublished=true
    --artifact "native-android-core-aar=${core_aar}"
    --artifact "native-android-ui-aar=${ui_aar}"
    --artifact "native-android-maven-repository=${maven_repository}"
    --artifact "native-ios-xcframework=${ios_framework}"
    --artifact "react-native-package=${react_native_package}"
    --artifact "uniapp-legacy-package=${uniapp_package}"
    --artifact "native-build-manifest=${native_manifest}"
    --artifact "native-build-checksums=${native_checksums}"
)
for artifact_path in "${artifacts[@]}"; do
    role="$(basename "${artifact_path}" | tr '[:upper:]_.' '[:lower:]--')"
    snapshot_arguments+=(--artifact "checksum-${role}=${artifact_path}.sha256")
done

"${script_dir}/snapshot-release-candidate.rb" "${snapshot_arguments[@]}"
if [[ "${state}" == rehearsal ]]; then
    echo "Created a rehearsal. It is intentionally ineligible for release acceptance." >&2
fi
