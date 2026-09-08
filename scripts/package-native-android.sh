#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
sfiora_parse_package_arguments "$@"
sfiora_guard_output "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}-maven.zip"
sfiora_guard_output "${sfiora_root}/dist/native-android/sfiora-${sfiora_version}.aar"
sfiora_guard_output "${sfiora_root}/dist/native-android/sfiora-ui-${sfiora_version}.aar"

sfiora_require_command zip

android_dir="${sfiora_root}/native/android"
artifact_dir="${sfiora_root}/dist/native-android"
repository_name="sfiora-${sfiora_version}-maven.zip"
repository_path="${artifact_dir}/${repository_name}"
temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-android-package.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
repository_dir="${temporary_dir}/maven"

"${android_dir}/gradlew" -p "${android_dir}" --no-daemon \
    -PsfioraCandidateRepository="${repository_dir}" \
    :sfiora:clean \
    :sfiora-ui:clean \
    :sfiora:publishReleasePublicationToCandidateRepository \
    :sfiora-ui:publishReleasePublicationToCandidateRepository

mkdir -p "${artifact_dir}"
for artifact_id in sfiora sfiora-ui; do
    repository_artifact="${repository_dir}/io/github/sandroxy/${artifact_id}/${sfiora_version}/${artifact_id}-${sfiora_version}.aar"
    artifact_path="${artifact_dir}/${artifact_id}-${sfiora_version}.aar"
    if [[ ! -f "${repository_artifact}" ]]; then
        echo "Maven publication did not produce ${repository_artifact}" >&2
        exit 1
    fi
    cp "${repository_artifact}" "${artifact_path}"
    sfiora_write_checksum "${artifact_path}"
done

rm -f "${repository_path}" "${repository_path}.sha256"
(
    cd "${repository_dir}"
    find . -type f \
        ! -name 'maven-metadata.xml' \
        ! -name 'maven-metadata.xml.*' \
        -print \
        | LC_ALL=C sort \
        | zip -q -X "${repository_path}" -@
)
sfiora_write_checksum "${repository_path}"

printf '%s\n' "${artifact_dir}/sfiora-${sfiora_version}.aar"
printf '%s\n' "${artifact_dir}/sfiora-ui-${sfiora_version}.aar"
printf '%s\n' "${repository_path}"
