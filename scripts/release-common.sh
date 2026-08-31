#!/usr/bin/env bash

set -euo pipefail

sfiora_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sfiora_root="$(cd "${sfiora_script_dir}/.." && pwd)"
sfiora_plugin_manifest="${sfiora_root}/plugin.json"

if ! command -v ruby >/dev/null 2>&1; then
    echo "Ruby is required to read plugin.json." >&2
    exit 1
fi

IFS=$'\t' read -r \
    sfiora_version \
    sfiora_repository \
    sfiora_android_group \
    sfiora_android_min_sdk \
    sfiora_ios_module \
    sfiora_ios_minimum \
    sfiora_react_native_package \
    sfiora_react_native_minimum \
    sfiora_uniapp_id \
    sfiora_uniapp_module \
    sfiora_uniapp_minimum_hbuilderx < <(
    ruby -rjson -e '
        manifest = JSON.parse(File.read(ARGV.fetch(0)))
        values = [
          manifest.fetch("version"),
          manifest.fetch("repository"),
          manifest.fetch("native").fetch("android").fetch("group"),
          manifest.fetch("native").fetch("android").fetch("minimumSdk"),
          manifest.fetch("native").fetch("ios").fetch("module"),
          manifest.fetch("native").fetch("ios").fetch("minimumVersion"),
          manifest.fetch("adapters").fetch("reactNative").fetch("package"),
          manifest.fetch("adapters").fetch("reactNative").fetch("minimumVersion"),
          manifest.fetch("adapters").fetch("uniApp").fetch("id"),
          manifest.fetch("adapters").fetch("uniApp").fetch("module"),
          manifest.fetch("adapters").fetch("uniApp").fetch("minimumHBuilderX")
        ]
        abort("plugin.json metadata must not contain tabs or newlines") if
          values.any? { |value| value.to_s.match?(/[\t\r\n]/) }
        puts(values.join("\t"))
    ' "${sfiora_plugin_manifest}"
)

if [[ ! "${sfiora_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid Sfiora semantic version: ${sfiora_version}" >&2
    exit 1
fi

sfiora_require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Required command is unavailable: ${command_name}" >&2
        exit 1
    fi
}

sfiora_sha256() {
    local file_path="$1"
    shasum -a 256 "${file_path}" | awk '{ print $1 }'
}

sfiora_write_checksum() {
    local file_path="$1"
    local file_name
    file_name="$(basename "${file_path}")"
    printf '%s  %s\n' "$(sfiora_sha256 "${file_path}")" "${file_name}" \
        > "${file_path}.sha256"
}

sfiora_verify_checksum() {
    local file_path="$1"
    local checksum_path="${file_path}.sha256"
    local expected_checksum
    local recorded_name
    local trailing_value

    if [[ ! -f "${file_path}" || ! -f "${checksum_path}" ]]; then
        echo "Artifact or checksum is missing: ${file_path}" >&2
        exit 1
    fi

    read -r expected_checksum recorded_name trailing_value < "${checksum_path}"
    if [[ ! "${expected_checksum}" =~ ^[0-9a-f]{64}$ ]] \
        || [[ "${recorded_name}" != "$(basename "${file_path}")" ]] \
        || [[ -n "${trailing_value:-}" ]]; then
        echo "Malformed checksum file: ${checksum_path}" >&2
        exit 1
    fi

    local actual_checksum
    actual_checksum="$(sfiora_sha256 "${file_path}")"
    if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
        echo "Checksum mismatch for ${file_path}" >&2
        echo "Expected: ${expected_checksum}" >&2
        echo "Actual:   ${actual_checksum}" >&2
        exit 1
    fi
}

sfiora_assert_version_unpublished() {
    if git -C "${sfiora_root}" show-ref --verify --quiet "refs/tags/${sfiora_version}"; then
        echo "Sfiora ${sfiora_version} already has a local tag and cannot be rebuilt." >&2
        exit 1
    fi

    local remote_output
    local remote_status
    set +e
    remote_output="$(git -C "${sfiora_root}" ls-remote --tags --refs origin \
        "refs/tags/${sfiora_version}" 2>&1)"
    remote_status=$?
    set -e
    if [[ ${remote_status} -ne 0 ]]; then
        echo "Unable to confirm that Sfiora ${sfiora_version} is unpublished on origin:" >&2
        printf '%s\n' "${remote_output}" >&2
        exit 1
    fi
    if [[ -n "${remote_output}" ]]; then
        echo "Sfiora ${sfiora_version} already exists on origin and cannot be rebuilt." >&2
        exit 1
    fi
}

sfiora_cleanup_temporary_directory() {
    local directory_path="$1"
    local temporary_root="${TMPDIR:-/tmp}"
    case "${directory_path}" in
        "${temporary_root%/}"/sfiora-*|/tmp/sfiora-*) rm -rf -- "${directory_path}" ;;
        *) echo "Refusing to remove unexpected temporary path: ${directory_path}" >&2 ;;
    esac
}
