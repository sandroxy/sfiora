#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/.." && pwd)"
source_file="${root}/adapters/uniapp/bridge.js"
destination="${root}/uni_modules/Sandrox-Sfiora/js_sdk/bridge.js"
case "${1:-}" in
    --check) cmp "${source_file}" "${destination}" ;;
    "") cp "${source_file}" "${destination}" ;;
    *) echo "Usage: $0 [--check]" >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || exit 1
