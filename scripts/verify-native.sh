#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "${target}" in
    android)
        "${script_dir}/verify-native-android.sh" "$@"
        ;;
    ios)
        "${script_dir}/verify-native-ios.sh" "$@"
        ;;
    all)
        android_arguments=()
        ios_arguments=()
        for argument in "$@"; do
            case "${argument}" in
                --skip-package)
                    android_arguments+=("${argument}")
                    ios_arguments+=("${argument}")
                    ;;
                --require-signatures)
                    android_arguments+=("${argument}")
                    ;;
                *)
                    echo "Unknown verification option: ${argument}" >&2
                    exit 1
                    ;;
            esac
        done
        "${script_dir}/verify-native-android.sh" "${android_arguments[@]}"
        "${script_dir}/verify-native-ios.sh" "${ios_arguments[@]}"
        ;;
    *)
        echo "Usage: $0 {android|ios|all} [verification options]" >&2
        exit 1
        ;;
esac
