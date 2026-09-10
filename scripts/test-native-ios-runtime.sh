#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-ios-runtime-tests.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT

if ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    ruby "${sfiora_root}/tests/ios-runtime/create-project.rb" "${sfiora_root}" "${temporary_dir}" "${sfiora_ios_minimum}"
else
    sfiora_require_command xcodeproj
    resolved_executable="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$(command -v xcodeproj)")"
    gem_root="$(cd "$(dirname "${resolved_executable}")/.." && pwd)/libexec"
    GEM_HOME="${gem_root}" ruby "${sfiora_root}/tests/ios-runtime/create-project.rb" "${sfiora_root}" "${temporary_dir}" "${sfiora_ios_minimum}"
fi

simulator_id="$(xcrun simctl list devices available --json | ruby -rjson -e '
  devices = JSON.parse(STDIN.read).fetch("devices").select { |runtime, _| runtime.include?(".iOS-") }.values.flatten
  device = devices.find { |entry| entry["state"] == "Booted" } || devices.first
  abort "An installed iOS Simulator runtime is required" unless device
  puts device.fetch("udid")
')"
if xcodebuild -quiet -project "${temporary_dir}/SfioraRuntimeTests.xcodeproj" \
    -scheme SfioraRuntimeTests -configuration Debug \
    -destination "platform=iOS Simulator,id=${simulator_id},arch=$(uname -m)" \
    -derivedDataPath "${temporary_dir}/build" -resultBundlePath "${temporary_dir}/results.xcresult" \
    CODE_SIGNING_ALLOWED=NO test; then
    xcrun xcresulttool get test-results summary --path "${temporary_dir}/results.xcresult" --compact | ruby -rjson -e '
      result = JSON.parse(STDIN.read)
      passed = result.fetch("passedTests")
      abort "No successful iOS runtime tests were recorded" unless passed > 0 && result.fetch("failedTests") == 0
      puts "Verified #{passed} production iOS callback tests on iOS Simulator."
    '
else
    if [[ -d "${temporary_dir}/results.xcresult" ]]; then
        xcrun xcresulttool get test-results summary --path "${temporary_dir}/results.xcresult" >&2 || true
    fi
    exit 1
fi
