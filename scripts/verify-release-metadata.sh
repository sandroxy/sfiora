#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

ruby -rjson -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    root = ARGV.fetch(1)

    expected_root_keys = %w[displayName id license native repository schemaVersion version]
    abort("plugin.json has unexpected root fields") unless
      manifest.keys.sort == expected_root_keys.sort
    abort("plugin.json schemaVersion must be 1") unless manifest["schemaVersion"] == 1
    abort("plugin.json id must be sfiora") unless manifest["id"] == "sfiora"
    abort("plugin.json displayName must be Sfiora") unless manifest["displayName"] == "Sfiora"
    abort("plugin.json license must be Apache-2.0") unless manifest["license"] == "Apache-2.0"
    abort("plugin.json repository is not canonical") unless
      manifest["repository"] == "https://github.com/sandroxy/sfiora.git"

    version = manifest.fetch("version")
    abort("Invalid semantic version: #{version}") unless
      version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[+-][0-9A-Za-z.-]+)?\z/)

    native = manifest.fetch("native")
    abort("plugin.json has unexpected native fields") unless native.keys.sort == %w[android ios]
    android = native.fetch("android")
    abort("plugin.json has unexpected Android fields") unless
      android.keys.sort == %w[artifacts group minimumSdk]
    abort("Unexpected Android Maven group") unless android["group"] == "io.github.sandroxy"
    abort("Unexpected Android artifact set") unless
      android["artifacts"] == ["sfiora", "sfiora-ui"]
    abort("Android minimum SDK must be 21") unless android["minimumSdk"] == 21

    ios = native.fetch("ios")
    abort("plugin.json has unexpected iOS fields") unless
      ios.keys.sort == %w[minimumVersion module]
    abort("Unexpected iOS module") unless ios["module"] == "Sfiora"
    abort("iOS minimum must be 13.0") unless ios["minimumVersion"] == "13.0"

    project_path = File.join(root, "native/ios/Sfiora.xcodeproj/project.pbxproj")
    project = File.read(project_path)
    abort("Sfiora.xcodeproj contains a machine-specific absolute path") if
      project.match?(%r{(?:/Users/|/home/|[A-Za-z]:\\)})
    abort("Sfiora.xcodeproj contains a version-specific SDK path") if
      project.include?("Developer/SDKs/")
    source_names = Dir.glob(File.join(root, "native/ios/Sources/Sfiora/*.swift"))
      .map { |path| File.basename(path) }
      .sort
    project_names = project.scan(
      /isa = PBXFileReference;[^\n]*lastKnownFileType = sourcecode\.swift; path = ([^;]+\.swift);/
    ).flatten.sort
    abort("Sfiora.xcodeproj source list differs from the Swift Package source directory") unless
      project_names == source_names

    marketing_versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.uniq
    abort("Xcode marketing version differs from plugin.json: #{marketing_versions.inspect}") unless
      marketing_versions == [version]
    deployment_targets = project.scan(/IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);/).flatten.uniq
    abort("Xcode minimum iOS differs from plugin.json: #{deployment_targets.inspect}") unless
      deployment_targets == [ios.fetch("minimumVersion")]
    bundle_identifiers = project.scan(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/).flatten.uniq
    abort("Unexpected iOS bundle identifier: #{bundle_identifiers.inspect}") unless
      bundle_identifiers == ["com.sandrox.sfiora"]

    ["sfiora", "sfiora-ui"].each do |artifact|
      gradle_file = File.read(File.join(root, "native/android/#{artifact}/build.gradle"))
      minimum = gradle_file[/minSdk\s*=\s*([0-9]+)/, 1]
      abort("#{artifact} minimum SDK differs from plugin.json") unless
        minimum == android.fetch("minimumSdk").to_s
    end

    package_swift = File.read(File.join(root, "Package.swift"))
    abort("Package.swift must expose the Sfiora source target") unless
      package_swift.include?(%q{name: "Sfiora"}) &&
      package_swift.include?(%q{path: "native/ios/Sources/Sfiora"})
    expected_platform = ".iOS(.v#{ios.fetch("minimumVersion").split(".").first})"
    abort("Package.swift minimum iOS differs from plugin.json") unless
      package_swift.include?(expected_platform)

    release_files = [
      File.join(root, "plugin.json"),
      File.join(root, "native/android/build.gradle"),
      File.join(root, "native/android/settings.gradle"),
      File.join(root, "native/android/sfiora/build.gradle"),
      File.join(root, "native/android/sfiora-ui/build.gradle"),
      *Dir.glob(File.join(root, "native/ios/Sfiora.xcodeproj/**/*")).select { |path| File.file?(path) },
      *Dir.glob(File.join(root, "scripts/*.sh"))
    ]
    stale_identity = release_files.each_with_object([]) do |path, matches|
      matches << path.delete_prefix("#{root}/") if
        File.binread(path).match?(/io\.gitee|gitee\.com/)
    end
    abort("Gitee publication identity remains in: #{stale_identity.join(", ")}") unless
      stale_identity.empty?
  ' "${sfiora_plugin_manifest}" "${sfiora_root}"

printf '%s\n' "Sfiora ${sfiora_version} release metadata is consistent."
