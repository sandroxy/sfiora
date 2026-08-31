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
    echo "Release manifest preparation requires a clean worktree." >&2
    echo "Use --allow-dirty only for local pipeline validation." >&2
    exit 1
fi

"${script_dir}/verify-release-metadata.sh"

native_manifest="${sfiora_root}/dist/native-release/sfiora-native-${sfiora_version}.json"
artifacts=(
    "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
    "${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
    "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}-maven.zip"
    "${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
    "${sfiora_root}/dist/react-native/sandrox-sfiora-${sfiora_version}.tgz"
    "${sfiora_root}/dist/uniapp/sfiora-uniapp-${sfiora_version}.zip"
)
if [[ ! -f "${native_manifest}" ]]; then
    echo "Native candidate manifest is missing: ${native_manifest}" >&2
    exit 1
fi
for artifact_path in "${artifacts[@]}"; do
    sfiora_verify_checksum "${artifact_path}"
done

native_signed="$(ruby -rjson -rdigest -e '
  manifest_path, version, allow_dirty, allow_unsigned, root, *files = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  abort("Unexpected native manifest schema") unless manifest.fetch("schemaVersion") == 1
  abort("Unexpected native manifest plugin") unless manifest.fetch("plugin") == "sfiora"
  abort("Unexpected native manifest version") unless manifest.fetch("version") == version
  abort("Native candidate must be clean") if
    allow_dirty != "1" && manifest.fetch("dirty")
  abort("Native Android Maven candidate must be signed") if
    allow_unsigned != "1" && !manifest.fetch("androidMavenSigned")
  indexed = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
  files.each do |file|
    relative = file.delete_prefix("#{root}/")
    entry = indexed.fetch(relative) { abort("Native manifest is missing #{relative}") }
    abort("Native manifest byte count differs for #{relative}") unless
      entry.fetch("bytes") == File.size(file)
    abort("Native manifest checksum differs for #{relative}") unless
      entry.fetch("sha256") == Digest::SHA256.file(file).hexdigest
  end
  puts manifest.fetch("androidMavenSigned")
' \
    "${native_manifest}" \
    "${sfiora_version}" \
    "${allow_dirty}" \
    "${allow_unsigned}" \
    "${sfiora_root}" \
    "${artifacts[0]}" \
    "${artifacts[1]}" \
    "${artifacts[2]}" \
    "${artifacts[3]}")"

react_native_package="$(tar -xOf "${artifacts[4]}" package/package.json)"
react_native_provenance="$(tar -xOf "${artifacts[4]}" package/sfiora-artifacts.json)"
uniapp_package="$(unzip -p "${artifacts[5]}" "${sfiora_uniapp_id}/package.json")"
uniapp_provenance="$(unzip -p "${artifacts[5]}" "${sfiora_uniapp_id}/sfiora-artifacts.json")"
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
  expected = {
    "sfiora.aar" => Digest::SHA256.file(core).hexdigest,
    "sfiora-ui.aar" => Digest::SHA256.file(ui).hexdigest
  }
  expected_ios = Digest::SHA256.file(ios).hexdigest
  [rn_provenance, uni_provenance].each do |raw|
    provenance = JSON.parse(raw)
    abort("Unexpected adapter provenance schema") unless
      provenance.fetch("schemaVersion") == 1 && provenance.fetch("version") == version
    android = provenance.dig("nativeArtifacts", "android")
    abort("Adapter does not embed the accepted Android candidates") unless
      expected.all? { |name, checksum| android.fetch(name) == checksum }
    abort("Adapter does not embed the accepted iOS candidate") unless
      provenance.dig("nativeArtifacts", "ios", "sfiora.xcframework.zip") == expected_ios
  end
' \
    "${sfiora_version}" \
    "${react_native_package}" \
    "${react_native_provenance}" \
    "${uniapp_package}" \
    "${uniapp_provenance}" \
    "${artifacts[0]}" \
    "${artifacts[1]}" \
    "${artifacts[3]}"

commit="$(git -C "${sfiora_root}" rev-parse HEAD)"
dirty=false
if [[ -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then
    dirty=true
fi
if [[ ${allow_dirty} -eq 0 ]] \
    && { [[ "${dirty}" == true ]] || [[ "${commit}" != "${initial_commit}" ]]; }; then
    echo "The source revision changed while preparing the release manifest." >&2
    exit 1
fi

release_dir="${sfiora_root}/dist/release"
manifest_path="${release_dir}/sfiora-${sfiora_version}.json"
checksums_path="${release_dir}/sfiora-${sfiora_version}-SHA256SUMS"
mkdir -p "${release_dir}"
(
    cd "${sfiora_root}"
    for artifact_path in "${artifacts[@]}"; do
        shasum -a 256 "${artifact_path#${sfiora_root}/}"
    done
) > "${checksums_path}"

ruby -rjson -rdigest -e '
  version, commit, dirty, signed, native_manifest, root, output, *files = ARGV
  payload = {
    schemaVersion: 1,
    plugin: "sfiora",
    version: version,
    commit: commit,
    dirty: dirty == "true",
    androidMavenSigned: signed == "true",
    nativeCandidateManifest: native_manifest.delete_prefix("#{root}/"),
    artifacts: files.map do |file|
      {
        file: file.delete_prefix("#{root}/"),
        bytes: File.size(file),
        sha256: Digest::SHA256.file(file).hexdigest
      }
    end
  }
  File.write(output, JSON.pretty_generate(payload) + "\n")
' \
    "${sfiora_version}" \
    "${commit}" \
    "${dirty}" \
    "${native_signed}" \
    "${native_manifest}" \
    "${sfiora_root}" \
    "${manifest_path}" \
    "${artifacts[@]}"

printf '%s\n' "${manifest_path}"
printf '%s\n' "${checksums_path}"
