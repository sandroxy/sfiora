#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "${target}" in
    android)
        "${script_dir}/package-native-android.sh" "$@"
        ;;
    ios)
        "${script_dir}/package-native-ios.sh" "$@"
        ;;
    all)
        "${script_dir}/package-native-android.sh" "$@"
        "${script_dir}/package-native-ios.sh" "$@"
        ;;
    *)
        echo "Usage: $0 {android|ios|all} [--replace]" >&2
        exit 1
        ;;
esac
