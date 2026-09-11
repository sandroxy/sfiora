#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 1; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec ruby "${script_dir}/verify-react-native.rb"
