#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' "Usage: $0 [--allow-dirty] [--allow-unsigned] [--replace]" \
        "       [--reuse-candidate FILE --reuse android|ios ...] [--signature-fingerprint FINGERPRINT]" \
        "Android reuse verifies existing signatures with the selected public key; no signing key is needed."
}
allow_dirty=0
allow_unsigned=0
package_arguments=()
reuse_candidate=""
reuse_groups=()
signature_fingerprint=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --allow-unsigned) allow_unsigned=1; shift ;;
        --replace) package_arguments+=(--replace); shift ;;
        --reuse-candidate)
            [[ -z "${reuse_candidate}" ]] || { echo "Duplicate reuse candidate" >&2; exit 1; }
            reuse_candidate="${2:?Missing candidate path}"; shift 2 ;;
        --reuse) reuse_groups+=("${2:?Missing reuse group}"); shift 2 ;;
        --signature-fingerprint)
            signature_fingerprint="${2:?Missing signing fingerprint}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
initial_commit="$(git -C "${sfiora_root}" rev-parse HEAD)"
reuse_android=0
reuse_ios=0
reuse_proof=""
if [[ -n "${reuse_candidate}" || ${#reuse_groups[@]} -gt 0 ]]; then
    if [[ -z "${reuse_candidate}" || ${#reuse_groups[@]} -eq 0 || ${allow_dirty} -ne 0 || ${allow_unsigned} -ne 0 ]]; then
        echo "Reuse requires an explicit candidate and groups, with no rehearsal flags." >&2
        exit 1
    fi
    ruby -I "${script_dir}" -rnative-artifact-reuse -e '
      groups = NativeArtifactReuse.groups
      abort("Unknown or duplicate reuse groups") unless ARGV.uniq == ARGV && (ARGV - groups.keys).empty?
    ' "${reuse_groups[@]}"
    for group in "${reuse_groups[@]}"; do
        case "${group}" in
            android) reuse_android=1 ;;
            ios) reuse_ios=1 ;;
        esac
    done
fi
if [[ ${reuse_android} -eq 1 ]]; then
    if [[ ! "${signature_fingerprint}" =~ ^([0-9A-F]{40}|[0-9A-F]{64})$ ]]; then
        echo "Android reuse requires --signature-fingerprint for an existing public key." >&2
        exit 1
    fi
elif [[ -n "${signature_fingerprint}" ]]; then
    echo "--signature-fingerprint applies only to Android reuse." >&2
    exit 1
fi

ios_binary_source_commit="${SFIORA_IOS_ACCEPTED_SOURCE_COMMIT:-${initial_commit}}"
ios_binary_promoted=false
ios_values=0
for value in "${SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP:-}" "${SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256:-}" "${SFIORA_IOS_ACCEPTED_SOURCE_COMMIT:-}"; do
    [[ -z "${value}" ]] || ios_values=$((ios_values + 1))
done
if [[ ${ios_values} -ne 0 && ${ios_values} -ne 3 ]]; then
    echo "Supply the complete accepted iOS archive, checksum, and source commit triplet." >&2
    exit 1
fi
if [[ ${reuse_ios} -eq 1 && ${ios_values} -ne 0 ]]; then
    echo "iOS candidate reuse cannot be combined with an accepted archive override." >&2
    exit 1
fi
if [[ ${ios_values} -eq 3 || ${reuse_ios} -eq 1 ]]; then
    ios_binary_promoted=true
fi
if [[ ${allow_dirty} -eq 0 && -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then
    echo "Release preparation requires a clean worktree. Use --allow-dirty only for rehearsal." >&2
    exit 1
fi
if [[ ${allow_unsigned} -eq 0 && ${reuse_android} -eq 0 && -z "${SFIORA_SIGNING_KEY:-}" ]]; then
    echo "A formal Android candidate requires SFIORA_SIGNING_KEY." >&2
    exit 1
fi
if [[ ${allow_dirty} -eq 0 && ${allow_unsigned} -eq 0 && "${ios_binary_promoted}" != true ]]; then
    echo "A formal candidate requires accepted iOS bytes or explicit iOS candidate reuse." >&2
    exit 1
fi

sfiora_assert_version_unpublished
"${script_dir}/verify-release-metadata.sh"
if [[ -n "${reuse_candidate}" ]]; then
    reuse_temporary_root="${TMPDIR:-/tmp}"
    reuse_work="$(mktemp -d "${reuse_temporary_root%/}/sfiora-native-reuse.XXXXXX")"
    trap 'reuse_exit=$?; sfiora_cleanup_temporary_directory "${reuse_work}"; exit "${reuse_exit}"' EXIT
    reuse_proof="${reuse_work}/proof.json"
    reuse_arguments=(--candidate "${reuse_candidate}" --proof "${reuse_proof}")
    for group in "${reuse_groups[@]}"; do reuse_arguments+=(--group "${group}"); done
    if [[ -n "${signature_fingerprint}" ]]; then
        reuse_arguments+=(--signature-fingerprint "${signature_fingerprint}")
    fi
    ruby "${script_dir}/reuse-native-artifacts.rb" "${reuse_arguments[@]}" ${package_arguments[@]+"${package_arguments[@]}"}
    build_groups="$(ruby -I "${script_dir}" -rnative-artifact-reuse -e 'puts NativeArtifactReuse.groups.keys - ARGV' "${reuse_groups[@]}")"
    while IFS= read -r group; do
        [[ -n "${group}" ]] || continue
        "${script_dir}/package-native-${group}.sh" ${package_arguments[@]+"${package_arguments[@]}"}
    done <<< "${build_groups}"
else
    "${script_dir}/package-native.sh" all ${package_arguments[@]+"${package_arguments[@]}"}
fi
"${script_dir}/verify-release-metadata.sh"
android_maven_signed=false
if [[ ${reuse_android} -eq 1 ]]; then
    "${script_dir}/verify-native-android.sh" --require-signatures --signature-fingerprint "${signature_fingerprint}"
    android_maven_signed=true
elif [[ -n "${SFIORA_SIGNING_KEY:-}" ]]; then
    "${script_dir}/verify-native-android.sh" --require-signatures
    android_maven_signed=true
else
    "${script_dir}/verify-native-android.sh"
fi
"${script_dir}/verify-native-ios.sh"
if [[ ${reuse_ios} -eq 1 ]]; then
    provenance="$(bash "${script_dir}/verify-ios-xcframework-provenance.sh" \
        "${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip" "${sfiora_version}" \
        "$(ruby "${script_dir}/native-input-digest.rb")")"
    read -r ios_binary_source_commit ios_source_digest <<< "${provenance}"
fi

commit="$(git -C "${sfiora_root}" rev-parse HEAD)"
dirty=false
if [[ -n "$(git -C "${sfiora_root}" status --porcelain)" ]]; then dirty=true; fi
if [[ ${allow_dirty} -eq 0 ]] && { [[ "${dirty}" == true ]] || [[ "${commit}" != "${initial_commit}" ]]; }; then
    echo "The source revision changed while preparing the release." >&2
    exit 1
fi
release_dir="${sfiora_root}/dist/native-release"
mkdir -p "${release_dir}"
ruby -I "${script_dir}" -rnative-release-manifest -e '
  version, commit, dirty, signed, ios_commit, promoted, proof_path, root, output = ARGV
  files = NativeReleaseManifest.paths(version).values
  payload = {
    "schemaVersion" => 2, "plugin" => "sfiora", "version" => version, "commit" => commit,
    "dirty" => dirty == "true", "androidMavenSigned" => signed == "true",
    "iosBinarySourceCommit" => ios_commit, "iosBinaryPromoted" => promoted == "true",
    "artifacts" => files.map do |relative|
      path = NativeReleaseManifest.regular_path!(root, relative)
      {"file" => relative, "bytes" => path.size, "sha256" => Digest::SHA256.file(path).hexdigest}
    end
  }
  payload["artifactReuse"] = JSON.parse(File.read(proof_path)) unless proof_path.empty?
  NativeReleaseManifest.validate!(payload, version: version)
  NativeReleaseManifest.verify_reuse!(payload, root: root)
  if payload.fetch("iosBinaryPromoted")
    NativeReleaseManifest.verify_ios!(payload, root: root,
      archive: File.join(root, NativeReleaseManifest.paths(version).fetch("native-ios-xcframework")))
  end
  manifest_path = File.join(output, "sfiora-native-#{version}.json")
  sums_path = File.join(output, "sfiora-native-#{version}-SHA256SUMS")
  File.write(manifest_path, JSON.pretty_generate(payload) + "\n")
  File.write(sums_path, payload.fetch("artifacts").map { |entry| "#{entry.fetch("sha256")}  #{entry.fetch("file")}\n" }.join)
  puts manifest_path, sums_path
' "${sfiora_version}" "${commit}" "${dirty}" "${android_maven_signed}" \
    "${ios_binary_source_commit}" "${ios_binary_promoted}" "${reuse_proof}" "${sfiora_root}" "${release_dir}"
