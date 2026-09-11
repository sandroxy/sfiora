#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require_relative "verify-react-native"

class ReactNativeVerificationTest < Minitest::Test
  class PackageVerifier < ReactNativeVerification
    private

    def run!(*arguments, **options)
      # CocoaPods is a macOS boundary; package refresh still uses real tar/npm/rsync/node.
      return if arguments.first == "pod"
      super
    end
  end

  def setup
    @temporary = Dir.mktmpdir("sfiora-rn-verification-test-")
    @root = Pathname.new(@temporary).realpath
    @work = @root.join(".build/react-native-verification")
    @runner = PackageVerifier.new(@root)
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def write(path, content)
    path.parent.mkpath
    path.write(content)
  end

  def test_prebuilt_defaults_preserve_both_architectures_and_explicit_source_selection
    assert_equal %w[0 0], ReactNativeVerification.ios_flags("legacy", {}).values
    assert_equal %w[1 1], ReactNativeVerification.ios_flags("new", {}).values
    flags = { "RCT_USE_PREBUILT_RNCORE" => "0", "RCT_USE_RN_DEP" => "0" }
    assert_equal flags, ReactNativeVerification.ios_flags("new", flags)
    assert_raises(ReactNativeVerification::Error) do
      ReactNativeVerification.ios_flags("new", "RCT_USE_RN_DEP" => "yes")
    end
  end

  def pod_installation(version: "0.81.5", prebuilt: true)
    pods = ["React-Core (#{version})"]
    if prebuilt
      ReactNativeVerification::PREBUILT_COMPONENTS.each_value do |name, framework|
        pods << "#{name} (#{version})"
        write(@root.join("Pods", framework, "Info.plist"), "framework")
      end
    end
    content = { "PODS" => pods }.to_yaml
    write(@root.join("Podfile.lock"), content)
    write(@root.join("Pods/Manifest.lock"), content)
  end

  def verify_pods(flags = ReactNativeVerification.ios_flags("new", {}))
    ReactNativeVerification.verify_pods!(@root, "0.81.5", flags)
  end

  def test_prebuilt_verification_rejects_silent_source_fallback
    pod_installation(prebuilt: false)
    error = assert_raises(ReactNativeVerification::Error) { verify_pods }
    assert_match(/source fallback/, error.message)
    verify_pods(ReactNativeVerification.ios_flags("legacy", {}))
  end

  def test_prebuilt_verification_checks_version_frameworks_and_installed_lock
    pod_installation
    verify_pods
    framework = @root.join("Pods/React-Core-prebuilt/React.xcframework/Info.plist")
    framework.unlink
    assert_raises(ReactNativeVerification::Error) { verify_pods }
    pod_installation(version: "0.81.4")
    assert_raises(ReactNativeVerification::Error) { verify_pods }
    pod_installation
    @root.join("Pods/Manifest.lock").write("stale")
    assert_raises(ReactNativeVerification::Error) { verify_pods }
  end

  def test_source_mode_rejects_retained_prebuilt_pods
    pod_installation
    assert_raises(ReactNativeVerification::Error) { verify_pods(ReactNativeVerification.ios_flags("legacy", {})) }
  end

  def make_artifact(value, obsolete: false)
    package = @root.join("input/package")
    FileUtils.remove_entry(package) if package.exist?
    write(package.join("package.json"), JSON.generate(name: "@sandrox/sfiora", version: "1.1.0", main: "index.js"))
    write(package.join("index.js"), "module.exports = #{value.to_json};\n")
    write(package.join("obsolete.js"), "obsolete") if obsolete
    write(package.join("README.md"), "readme")
    write(package.join("CHANGELOG.md"), "changes")
    write(@root.join("adapters/react-native/README.md"), "readme")
    write(@root.join("CHANGELOG.md"), "changes")
    artifact = @root.join("sfiora.tgz")
    assert system({ "COPYFILE_DISABLE" => "1" }, "tar", "-czf", artifact.to_s, "-C", package.parent.to_s, "package")
    @runner.instance_variable_set(:@artifact, artifact)
    Digest::SHA256.file(artifact).hexdigest
  end

  def test_same_version_refresh_uses_new_bytes_removes_old_sources_and_retains_builds
    template = @root.join("tests/consumers/react-native")
    write(template.join("package.json"), JSON.generate(name: "consumer", version: "1.0.0", private: true))
    write(template.join("verify.cjs"), "require('@sandrox/sfiora');")
    write(template.join("react-native-stub/package.json"), JSON.generate(name: "react-native", version: "0.0.0"))
    write(template.join("android/build/should-not-copy"), "source build output")
    @work.join("logs").mkpath
    @runner.send(:prepare_inputs, make_artifact("first", obsolete: true))
    installed = @work.join("consumer/node_modules/@sandrox/sfiora")
    assert installed.join("obsolete.js").file?
    cache = @work.join("consumer/android/build/new/cached.o")
    pods = @work.join("consumer/ios-new/Pods/cached.a")
    write(cache, "build cache")
    write(pods, "pods cache")
    write(@work.join("consumer/obsolete-template.js"), "old template")
    second = make_artifact("second")
    @runner.send(:prepare_inputs, second)
    assert_equal "module.exports = \"second\";\n", installed.join("index.js").read
    refute installed.join("obsolete.js").exist?
    refute @work.join("package/obsolete.js").exist?
    refute @work.join("consumer/obsolete-template.js").exist?
    refute @work.join("consumer/android/build/should-not-copy").exist?
    assert_equal "build cache", cache.read
    assert_equal "pods cache", pods.read
    assert_equal ["#{second}-sfiora.tgz"], @work.join("artifacts").children.map { |path| path.basename.to_s }

    source = @work.join("package/index.js")
    time = Time.at(1_600_000_000)
    File.utime(time, time, source)
    @runner.send(:prepare_inputs, second)
    assert_equal time, source.mtime, "unchanged input must not invalidate native compilation"
  end

  def test_workspace_lock_blocks_overlap_and_releases_after_failure
    other = ReactNativeVerification.new(@root)
    @runner.send(:with_workspace) do
      assert_raises(ReactNativeVerification::Error) { other.send(:with_workspace) { flunk "lock was bypassed" } }
    end
    assert_raises(RuntimeError) { @runner.send(:with_workspace) { raise "interrupted build" } }
    other.send(:with_workspace) { assert true }
  end

  def test_workspace_symlink_does_not_touch_external_files
    outside = @root.join("external")
    outside.mkpath
    write(outside.join("sentinel"), "retain")
    File.symlink(outside, @root.join(".build"))
    assert_raises(ReactNativeVerification::Error) { @runner.send(:with_workspace) { flunk "unsafe workspace" } }
    assert_equal "retain", outside.join("sentinel").read
  end
end
