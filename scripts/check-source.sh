#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/.." && pwd)"
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 1; }
cd "${root}"
git diff --check
bash scripts/verify-release-metadata.sh --allow-pending-ios
bash scripts/sync-uniapp-js.sh --check
node --test tests/js/*.test.mjs
for path in scripts/*.rb tests/ios-runtime/*.rb; do ruby -c "${path}" >/dev/null; done
for path in scripts/*.sh adapters/uniapp/ios/*.sh; do bash -n "${path}"; done
ruby scripts/test-release-policy.rb
ruby scripts/test-adapter-provenance.rb
ruby scripts/test-publish-candidate.rb
python3 .github/scripts/test-release-assets.py
ruby scripts/test-native-artifact-reuse.rb
ruby scripts/test-maven-signatures.rb
ruby scripts/test-react-native-verification.rb
if command -v xcrun >/dev/null 2>&1; then
    xcrun swift-format lint --strict --recursive \
        Package.swift native/ios/Package.swift native/ios/Sources tests/ios tests/ios-runtime scripts/fixtures \
        adapters/shared/Package.swift adapters/shared/ios/Sources adapters/shared/ios/Tests
    plutil -lint native/ios/Sfiora.xcodeproj/project.pbxproj \
        adapters/uniapp/ios/SfioraUniApp.xcodeproj/project.pbxproj \
        adapters/uniapp/ios/SfioraUniRuntime.xcodeproj/project.pbxproj >/dev/null
fi
printf '%s\n' "Sfiora source checks passed. Native compilation and physical-device acceptance are separate."
