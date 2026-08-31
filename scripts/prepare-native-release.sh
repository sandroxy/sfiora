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
initial_commit="$(git -C "${sfiora_root}" rev-parse HEAD)"

sfiora_assert_version_unpublished

if [[ ${allow_dirty} -eq 0 ]] \
    && [[ -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then
    echo "Release preparation requires a clean worktree." >&2
    echo "Use --allow-dirty only for local pipeline validation." >&2
    exit 1
fi

if [[ ${allow_unsigned} -eq 0 && -z "${SFIORA_SIGNING_KEY:-}" ]]; then
    echo "A formal Android candidate requires SFIORA_SIGNING_KEY." >&2
    echo "Use --allow-unsigned only for local pipeline validation." >&2
    exit 1
fi

"${script_dir}/verify-release-metadata.sh"
"${script_dir}/package-native.sh" all
android_maven_signed=false
if [[ -n "${SFIORA_SIGNING_KEY:-}" ]]; then
    "${script_dir}/verify-native-android.sh" --skip-package --require-signatures
    android_maven_signed=true
else
    "${script_dir}/verify-native-android.sh" --skip-package
fi
"${script_dir}/verify-native-ios.sh" --skip-package

release_dir="${sfiora_root}/dist/native-release"
manifest_path="${release_dir}/sfiora-native-${sfiora_version}.json"
checksums_path="${release_dir}/sfiora-native-${sfiora_version}-SHA256SUMS"
mkdir -p "${release_dir}"

artifacts=(
    "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
    "${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"
    "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}-maven.zip"
    "${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip"
)
for artifact_path in "${artifacts[@]}"; do
    if [[ ! -f "${artifact_path}" ]]; then
        echo "Native release artifact is missing: ${artifact_path}" >&2
        exit 1
    fi
done

(
    cd "${sfiora_root}"
    for artifact_path in "${artifacts[@]}"; do
        shasum -a 256 "${artifact_path#${sfiora_root}/}"
    done
) > "${checksums_path}"

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
ruby -rjson -rdigest -e '
    version, commit, dirty, signed, root, output, *files = ARGV
    payload = {
      schemaVersion: 1,
      plugin: "sfiora",
      version: version,
      commit: commit,
      dirty: dirty == "true",
      androidMavenSigned: signed == "true",
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
    "${android_maven_signed}" \
    "${sfiora_root}" \
    "${manifest_path}" \
    "${artifacts[@]}"

printf '%s\n' "${manifest_path}"
printf '%s\n' "${checksums_path}"
