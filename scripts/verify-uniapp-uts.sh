#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 1; }
archive="${sfiora_root}/dist/uniapp/sfiora-uniapp-uts-${sfiora_version}.zip"
sfiora_verify_checksum "${archive}"
temporary_root="${TMPDIR:-/tmp}"
temporary_dir="$(mktemp -d "${temporary_root%/}/sfiora-uts-verify.XXXXXX")"
trap 'sfiora_cleanup_temporary_directory "${temporary_dir}"' EXIT
zipinfo -1 "${archive}" > "${temporary_dir}/entries"
ruby -e '
  entries = File.readlines(ARGV[0], chomp: true)
  abort("Duplicate ZIP entries") unless entries.uniq == entries
  abort("Unsafe ZIP entry") if entries.empty? || entries.any? { |name|
    name.start_with?("/") || name.include?("\\") || name.split("/").include?("..")
  }
' "${temporary_dir}/entries"
mkdir -p "${temporary_dir}/artifact/${sfiora_uniapp_id}"
ditto -x -k "${archive}" "${temporary_dir}/artifact/${sfiora_uniapp_id}"
package_root="${temporary_dir}/artifact/${sfiora_uniapp_id}"
if [[ -n "$(find "${package_root}" -type l -print -quit)" ]]; then
    echo "UTS package contains a symbolic link" >&2; exit 1
fi
cmp "${package_root}/readme.md" "${sfiora_root}/adapters/uniapp/README.md"
cmp "${package_root}/changelog.md" "${sfiora_root}/CHANGELOG.md"
ruby -rjson -rdigest -ropen3 -e '
  root, source, version = ARGV
  package = JSON.parse(File.read("#{root}/package.json"))
  abort("UTS package identity differs") unless package["id"] == "Sandrox-Sfiora" &&
    package["version"] == version && package.dig("dcloudext", "type") == "uts"
  source_root = "#{source}/uni_modules/Sandrox-Sfiora"
  paths, status = Open3.capture2("git", "-C", source, "ls-files", "-cz", "--others", "--exclude-standard", "--", "uni_modules/Sandrox-Sfiora")
  abort("Unable to inventory UTS source") unless status.success?
  paths.split("\0").each do |relative_source|
    path = "#{source}/#{relative_source}"
    relative = path.delete_prefix("#{source_root}/")
    abort("Packaged UTS source differs: #{relative}") unless File.binread(path) == File.binread("#{root}/#{relative}")
  end
  forbidden = Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).find do |path|
    relative = path.delete_prefix("#{root}/")
    relative.split("/").any? { |part| %w[.git .gradle .build .DS_Store node_modules build build-runtime unpackage].include?(part) } ||
      path.match?(/\.(java|kt|swift|m|mm|xcodeproj|xcworkspace|gradle)\z/)
  end
  abort("Unexpected source or local output in UTS package: #{forbidden}") if forbidden
  provenance = JSON.parse(File.read("#{root}/sfiora-artifacts.json"))
  abort("UTS provenance identity differs") unless provenance["schemaVersion"] == 1 && provenance["version"] == version
  libs = "#{root}/utssdk/app-android/libs"
  expected = %w[sfiora.aar sfiora-ui.aar sfiora-bridge-support.aar].sort
  abort("Unexpected UTS Android binaries") unless Dir.children(libs).sort == expected
  expected.each do |name|
    digest = Digest::SHA256.file("#{libs}/#{name}").hexdigest
    abort("UTS Android provenance differs: #{name}") unless provenance.dig("nativeArtifacts", "android", name) == digest
  end
  %w[sfiora sfiora-ui].each do |name|
    abort("UTS Android core differs") unless File.binread("#{libs}/#{name}.aar") ==
      File.binread("#{source}/dist/native-android/#{name}-#{version}.aar")
  end
  ios = "#{source}/dist/native-ios/sfiora-#{version}.xcframework.zip"
  abort("UTS iOS provenance differs") unless provenance.dig("nativeArtifacts", "ios", "sfiora.xcframework.zip") == Digest::SHA256.file(ios).hexdigest
' "${package_root}" "${sfiora_root}" "${sfiora_version}"
ditto -x -k "${sfiora_root}/dist/native-ios/sfiora-${sfiora_version}.xcframework.zip" "${temporary_dir}/core"
diff -qr "${temporary_dir}/core/Sfiora.xcframework/ios-arm64/Sfiora.framework" \
    "${package_root}/utssdk/app-ios/Frameworks/Sfiora.framework" >/dev/null
runtime="${package_root}/utssdk/app-ios/Frameworks/SfioraUniRuntime.framework"
[[ -f "${runtime}/SfioraUniRuntime" ]] || { echo "UTS runtime framework is missing" >&2; exit 1; }
nm -gU "${runtime}/SfioraUniRuntime" | grep -F 'OBJC_CLASS_$_SfioraBridgeCoordinator' >/dev/null
bash "${script_dir}/verify-uniapp-uts-compiler.sh" "${archive}"
printf '%s\n' "Verified classic UTS and uni-app x artifact consumers."
