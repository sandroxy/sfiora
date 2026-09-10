#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/release-common.sh"

allow_pending_ios=false
case "${1:-}" in
    --allow-pending-ios) allow_pending_ios=true; shift ;;
    "") ;;
    *) echo "Usage: $0 [--allow-pending-ios]" >&2; exit 1 ;;
esac
[[ $# -eq 0 ]] || { echo "Unexpected arguments" >&2; exit 1; }

ruby -rjson -rdigest -rrubygems -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    root = ARGV.fetch(1)

    expected_root_keys = %w[adapters displayName id license native repository schemaVersion version]
    abort("plugin.json has unexpected root fields") unless
      manifest.keys.sort == expected_root_keys.sort
    abort("plugin.json schemaVersion must be 1") unless manifest["schemaVersion"] == 1
    abort("plugin.json id must be sfiora") unless manifest["id"] == "sfiora"
    abort("plugin.json displayName must be Sfiora") unless manifest["displayName"] == "Sfiora"
    abort("plugin.json license must be Apache-2.0") unless manifest["license"] == "Apache-2.0"
    abort("plugin.json repository is not canonical") unless
      manifest["repository"] == "https://github.com/sandroxy/sfiora.git"

    adapters = manifest.fetch("adapters")
    abort("plugin.json has unexpected adapter fields") unless
      adapters.keys.sort == %w[reactNative uniApp uniAppUts]
    react_native = adapters.fetch("reactNative")
    abort("plugin.json has unexpected React Native fields") unless
      react_native.keys.sort == %w[minimumVersion package]
    abort("Unexpected React Native package") unless
      react_native["package"] == "@sandrox/sfiora"
    abort("React Native minimum must be 0.76") unless
      react_native["minimumVersion"] == "0.76"
    uni_app = adapters.fetch("uniApp")
    abort("plugin.json has unexpected UniApp fields") unless
      uni_app.keys.sort == %w[id kind minimumHBuilderX module]
    abort("Unexpected UniApp adapter identity") unless
      uni_app == {
        "kind" => "nativeplugin",
        "id" => "Sandrox-Sfiora",
        "module" => "Sfiora",
        "minimumHBuilderX" => "5.24"
      }

    uts = adapters.fetch("uniAppUts")
    abort("Unexpected UTS product metadata") unless uts == {
      "kind" => "uts", "id" => "Sandrox-Sfiora", "sourceRoot" => "uni_modules/Sandrox-Sfiora",
      "minimumHBuilderX" => "5.24", "runtimes" => ["uni-app", "uni-app-x"]
    }
    uts_package = JSON.parse(File.read(File.join(root, uts.fetch("sourceRoot"), "package.json")))
    abort("UTS package identity differs") unless
      uts_package["id"] == uts["id"] && uts_package["version"] == manifest["version"] &&
        uts_package.dig("dcloudext", "type") == uts["kind"] && uts_package["license"] == manifest["license"]
    uts_root = File.join(root, uts.fetch("sourceRoot"), "utssdk")
    abort("UTS Android minimum differs") unless JSON.parse(File.read(File.join(uts_root, "app-android/config.json")))["minSdkVersion"] == 21
    abort("UTS iOS minimum differs") unless JSON.parse(File.read(File.join(uts_root, "app-ios/config.json")))["deploymentTarget"] == "13.0"
    abort("UTS Swift runtime source project is missing") unless File.file?(File.join(root, "adapters/uniapp/ios/SfioraUniRuntime.xcodeproj/project.pbxproj"))

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
      ios.keys.sort == %w[distribution minimumVersion module]
    abort("iOS distribution must be a binary Swift Package") unless
      ios["distribution"] == "binarySwiftPackage"
    abort("Unexpected iOS module") unless ios["module"] == "Sfiora"
    abort("iOS minimum must be 13.0") unless ios["minimumVersion"] == "13.0"

    react_package = JSON.parse(
      File.read(File.join(root, "adapters/react-native/package.json"))
    )
    abort("React Native package name differs from plugin.json") unless
      react_package["name"] == react_native["package"]
    abort("React Native package version differs from plugin.json") unless
      react_package["version"] == version
    abort("React Native peer minimum differs from plugin.json") unless
      react_package.dig("peerDependencies", "react-native") ==
        ">=#{react_native.fetch("minimumVersion")}"
    abort("React Native package repository is not canonical") unless
      react_package.dig("repository", "url") == manifest["repository"]
    abort("React Native package license differs from plugin.json") unless
      react_package["license"] == manifest["license"]

    react_gradle = File.read(
      File.join(root, "adapters/react-native/android/build.gradle")
    )
    react_minimum = react_gradle[
      /minSdk\s*=\s*safeExtGet\("minSdkVersion",\s*([0-9]+)\)/,
      1
    ]
    abort("React Native Android minimum differs from plugin.json") unless
      react_minimum == android.fetch("minimumSdk").to_s

    react_podspec = File.read(
      File.join(root, "adapters/react-native/SfioraReactNative.podspec")
    )
    react_ios_minimum = react_podspec[
      /spec\.platform\s*=\s*:ios,\s*"([^"]+)"/,
      1
    ]
    abort("React Native iOS minimum differs from plugin.json") unless
      react_ios_minimum == ios.fetch("minimumVersion")

    uni_template = JSON.parse(
      File.read(
        File.join(root, "adapters/uniapp/packaging/package.template.json")
      ).gsub("@VERSION@", version)
    )
    abort("UniApp package name differs from plugin.json") unless
      uni_template["name"] == manifest["displayName"]
    abort("UniApp package id differs from plugin.json") unless
      uni_template["id"] == uni_app["id"]
    abort("UniApp package version differs from plugin.json") unless
      uni_template["version"] == version
    abort("UniApp package kind differs from plugin.json") unless
      uni_template["_dp_type"] == uni_app["kind"]
    uni_native = uni_template.fetch("_dp_nativeplugin")
    expected_android_module = [{
      "type" => "module",
      "name" => uni_app.fetch("module"),
      "class" => "com.sandrox.sfiora.uniapp.SfioraUniModule"
    }]
    expected_ios_module = [{
      "type" => "module",
      "name" => uni_app.fetch("module"),
      "class" => "SfioraUniModule"
    }]
    abort("Unexpected UniApp Android module metadata") unless
      uni_native.dig("android", "plugins") == expected_android_module
    abort("Unexpected UniApp iOS module metadata") unless
      uni_native.dig("ios", "plugins") == expected_ios_module
    abort("UniApp Android minimum differs from plugin.json") unless
      uni_native.dig("android", "minSdkVersion") ==
        android.fetch("minimumSdk").to_s
    abort("UniApp iOS minimum differs from plugin.json") unless
      uni_native.dig("ios", "deploymentTarget") == ios.fetch("minimumVersion")

    uni_gradle = File.read(File.join(root, "adapters/uniapp/android/build.gradle"))
    uni_minimum = uni_gradle[
      /minSdk\s*=\s*safeExtGet\("minSdkVersion",\s*([0-9]+)\)/,
      1
    ]
    abort("UniApp Android build minimum differs from plugin.json") unless
      uni_minimum == android.fetch("minimumSdk").to_s

    uni_project = File.read(
      File.join(root, "adapters/uniapp/ios/SfioraUniApp.xcodeproj/project.pbxproj")
    )
    uni_marketing_versions =
      uni_project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.uniq
    abort("UniApp iOS version differs from plugin.json") unless
      uni_marketing_versions == [version]
    uni_deployment_targets =
      uni_project.scan(/IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);/).flatten.uniq
    abort("UniApp iOS minimum differs from plugin.json") unless
      uni_deployment_targets == [ios.fetch("minimumVersion")]

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
    abort("Sfiora.xcodeproj source list differs from the canonical iOS source directory") unless
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
    abort("Package.swift must expose the Sfiora binary target") unless
      package_swift.include?(%q{.binaryTarget(}) &&
      package_swift.include?(%q{name: "Sfiora"}) &&
      !package_swift.include?(%q{path: "native/ios/Sources/Sfiora"})
    expected_platform = ".iOS(.v#{ios.fetch("minimumVersion").split(".").first})"
    abort("Package.swift minimum iOS differs from plugin.json") unless
      package_swift.include?(expected_platform)
    package_version = package_swift[/let sfioraVersion = "([^"]+)"/, 1]
    pending_ios = ARGV.fetch(2) == "true" &&
      package_version&.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/) &&
      Gem::Version.new(package_version) < Gem::Version.new(version)
    abort("Package.swift is pending the current iOS archive version/checksum; complete the two-commit release handoff") unless
      package_version == version || pending_ios
    abort("Package.swift release base URL is invalid") unless package_swift.include?(
      %q{let sfioraReleaseBaseURL =} + "\n" +
        %q{    "https://github.com/sandroxy/sfiora/releases/download/\(sfioraVersion)"}
    )
    abort("Package.swift binary URL is invalid") unless package_swift.include?(
      %q{let sfioraBinaryURL = "\(sfioraReleaseBaseURL)/sfiora-\(sfioraVersion).xcframework.zip"}
    ) && package_swift.include?(%q{url: sfioraBinaryURL})
    binary_checksum = package_swift[/let sfioraBinaryChecksum =\s*"([0-9a-f]+)"/, 1]
    abort("Package.swift binary checksum is invalid") unless
      binary_checksum&.match?(/\A[0-9a-f]{64}\z/) &&
        package_swift.include?(%q{checksum: sfioraBinaryChecksum})
    puts("iOS binary manifest remains at #{package_version}; #{version} release metadata handoff is pending.") if pending_ios
    ios_artifact = File.join(root, "dist/native-ios/sfiora-#{package_version}.xcframework.zip")
    if File.file?(ios_artifact)
      abort("Package.swift checksum differs from the local iOS artifact") unless
        Digest::SHA256.file(ios_artifact).hexdigest == binary_checksum
    end

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
  ' "${sfiora_plugin_manifest}" "${sfiora_root}" "${allow_pending_ios}"

printf '%s\n' "Sfiora ${sfiora_version} metadata checks passed."
