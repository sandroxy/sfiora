#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "pathname"
require "tmpdir"
require "yaml"

class ReactNativeVerification
  class Error < StandardError; end

  PREBUILT_COMPONENTS = {
    "RCT_USE_PREBUILT_RNCORE" => ["React-Core-prebuilt", "React-Core-prebuilt/React.xcframework"],
    "RCT_USE_RN_DEP" => ["ReactNativeDependencies", "ReactNativeDependencies/framework/packages/react-native/ReactNativeDependencies.xcframework"]
  }.freeze
  GENERATED = %w[.DS_Store .git .gradle .build .cxx build build-runtime DerivedData node_modules Pods].freeze
  IOS_GENERATED = %w[Pods build Podfile.lock SfioraConsumer.xcodeproj SfioraConsumer.xcworkspace .project-generator-sha256].freeze

  def initialize(root = Pathname.new(__dir__).parent, environment: ENV)
    @root = Pathname.new(root).realpath
    @environment = environment.to_h
    @work = @root.join(".build/react-native-verification")
    @consumer = @work.join("consumer")
    @package = @work.join("package")
  end

  def self.ios_flags(architecture, environment = ENV)
    raise Error, "Unknown RN architecture: #{architecture}" unless %w[legacy new].include?(architecture)

    PREBUILT_COMPONENTS.keys.to_h do |key|
      value = environment.fetch(key, architecture == "legacy" ? "0" : "1")
      raise Error, "#{key} must be 0 or 1" unless %w[0 1].include?(value)
      [key, value]
    end
  end

  def self.verify_pods!(project, version, flags)
    project = Pathname.new(project)
    lock = project.join("Podfile.lock")
    installed = project.join("Pods/Manifest.lock")
    raise Error, "CocoaPods installation is incomplete: #{project}" unless
      lock.file? && installed.file? && lock.binread == installed.binread

    pods = YAML.safe_load(lock.read, permitted_classes: [Symbol]).fetch("PODS").map do |entry|
      entry.is_a?(Hash) ? entry.keys.fetch(0) : entry
    end
    raise Error, "Installed React-Core differs from RN #{version}" unless pods.include?("React-Core (#{version})")
    PREBUILT_COMPONENTS.each do |key, (name, framework)|
      present = pods.any? { |pod| pod.start_with?("#{name} (") }
      if flags.fetch(key) == "0"
        raise Error, "#{name} remains installed despite #{key}=0" if present
      else
        raise Error, "Expected precompiled #{name} #{version}; source fallback is not accepted" unless
          pods.include?("#{name} (#{version})")
        raise Error, "Precompiled framework is missing: #{framework}" unless
          project.join("Pods", framework, "Info.plist").file?
      end
    end
  end

  def run
    %w[diff node npm pod rsync ruby tar xcodebuild].each { |name| executable!(name) }
    @rn = external_package!("SFIORA_REACT_NATIVE_PATH")
    @gradle_plugin = external_package!("SFIORA_REACT_NATIVE_GRADLE_PLUGIN_PATH")
    @codegen = external_package!("SFIORA_REACT_NATIVE_CODEGEN_PATH")
    @rn_version = JSON.parse(@rn.join("package.json").read).fetch("version")
    @ios_flags = %w[legacy new].to_h { |architecture| [architecture, self.class.ios_flags(architecture, @environment)] }
    version = JSON.parse(@root.join("plugin.json").read).fetch("version")
    @artifact = @root.join("dist/react-native/sandrox-sfiora-#{version}.tgz")
    expected = @artifact.sub_ext(".tgz.sha256").read.split.fetch(0)
    raise Error, "React Native artifact checksum differs" unless
      expected.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(@artifact).hexdigest == expected

    with_workspace do
      @work.join("logs").mkpath
      puts "RN verification workspace: #{@work}"
      prepare_inputs(expected)
      verify_android
      verify_ios
      run!("node", "--test", @root.join("tests/js/bridge-wrappers.test.mjs"))
      run!("diff", "-qr", @package, @consumer.join("node_modules/@sandrox/sfiora"), log: "installed-package.log")
      raise Error, "React Native artifact changed during verification" unless Digest::SHA256.file(@artifact).hexdigest == expected
      puts "React Native artifact verification passed for legacy and new architectures on iOS devices and simulators."
    end
  end

  private

  def executable!(name)
    path = @environment.fetch("PATH").split(File::PATH_SEPARATOR).map { |entry| File.join(entry, name) }
      .find { |entry| File.file?(entry) && File.executable?(entry) }
    raise Error, "Required command is unavailable: #{name}" unless path
    path
  end

  def external_package!(key)
    value = @environment.fetch(key, "")
    path = Pathname.new(value)
    raise Error, "Set #{key} to an installed package directory" unless
      path.absolute? && path.join("package.json").file?
    path.realpath
  end

  def directory!(path)
    path.ascend do |parent|
      raise Error, "Verification workspace uses a symbolic link: #{parent}" if parent.symlink?
      break if parent == @root
    end
    path.mkpath
  end

  def with_workspace
    directory!(@work)
    lock_path = @work.join(".lock")
    raise Error, "Verification lock is a symbolic link" if lock_path.symlink?
    File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
      raise Error, "React Native verification is already running in #{@work}" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      yield
    end
  end

  def run!(*arguments, chdir: @root, environment: {}, log: nil)
    command = arguments.map(&:to_s)
    options = { chdir: chdir.to_s }
    options.merge!(out: @work.join("logs", log).to_s, err: [:child, :out]) if log
    return if system(@environment.merge(environment), *command, **options)

    warn @work.join("logs", log).read.lines.last(80).join if log
    raise Error, "#{command.first} failed; #{log ? "see #{@work.join('logs', log)}" : 'verification stopped'}"
  end

  def sync(source, destination, exclude: [])
    directory!(destination)
    run!("rsync", "-rlpc", "--delete", *exclude.map { |name| "--exclude=#{name}" }, "#{source}/", "#{destination}/")
  end

  def write_changed(path, content)
    path.write(content) unless path.file? && path.read == content
  end

  def prepare_inputs(checksum)
    Dir.mktmpdir("sfiora-react-native-input-") do |temporary|
      incoming = Pathname.new(temporary)
      run!("tar", "-xzf", @artifact, "--strip-components", "1", "-C", incoming)
      Find.find(incoming.to_s) do |path|
        raise Error, "React Native package contains generated state: #{path}" if GENERATED.include?(File.basename(path))
      end
      %w[README.md CHANGELOG.md].each do |name|
        source = name == "README.md" ? @root.join("adapters/react-native", name) : @root.join(name)
        raise Error, "Packaged #{name} differs from the source" unless incoming.join(name).binread == source.binread
      end
      # Native build outputs live outside this pristine package tree.
      sync(incoming, @package)
    end

    template = @root.join("tests/consumers/react-native")
    sync(template, @consumer, exclude: GENERATED + IOS_GENERATED + %w[/package.json /ios-legacy /ios-new])
    artifacts = @work.join("artifacts")
    directory!(artifacts)
    staged = artifacts.join("#{checksum}-sfiora.tgz")
    raise Error, "Staged npm archive is a symbolic link" if staged.symlink?
    FileUtils.cp(@artifact, staged) unless staged.file? && Digest::SHA256.file(staged).hexdigest == checksum
    package = JSON.parse(template.join("package.json").read)
    package["dependencies"] = { "@sandrox/sfiora" => "file:#{staged.relative_path_from(@consumer)}" }
    write_changed(@consumer.join("package.json"), JSON.pretty_generate(package) + "\n")
    run!("npm", "install", "--ignore-scripts", "--legacy-peer-deps", "--no-package-lock", "--no-audit", "--no-fund",
      chdir: @consumer, log: "npm-install.log")
    sync(@consumer.join("react-native-stub"), @consumer.join("node_modules/react-native"))
    run!("diff", "-qr", @package, @consumer.join("node_modules/@sandrox/sfiora"), log: "installed-package.log")
    run!("node", "verify.cjs", chdir: @consumer)
    run!("pod", "ipc", "spec", @package.join("SfioraReactNative.podspec"), log: "podspec.log")
    artifacts.children.each do |path|
      path.unlink if path != staged && path.file? && !path.symlink? && path.basename.to_s.match?(/\A[0-9a-f]{64}-sfiora\.tgz\z/)
    end
  end

  def verify_android
    %w[false true].each do |architecture|
      puts "Verifying RN Android newArchEnabled=#{architecture}"
      run!(@root.join("native/android/gradlew"), "-p", @consumer.join("android"), "--no-daemon",
        "-PnewArchEnabled=#{architecture}", "-PminSdkVersion=24", "-PsfioraReactNativeVersion=#{@rn_version}",
        "-PsfioraReactNativePath=#{@rn}", "-PsfioraReactNativeGradlePluginPath=#{@gradle_plugin}",
        "-PsfioraReactNativeCodegenPath=#{@codegen}", "-PreactNativeGradlePluginPath=#{@gradle_plugin}",
        "-PsfioraPackagePath=#{@package}", ":app:compileDebugJavaWithJavac", ":sfiora:testDebugUnitTest",
        log: "android-#{architecture == 'true' ? 'new' : 'legacy'}.log")
    end
  end

  def create_ios_project(project)
    generator = project.join("create-project.rb")
    checksum = Digest::SHA256.file(generator).hexdigest
    marker = project.join(".project-generator-sha256")
    return if project.join("SfioraConsumer.xcodeproj/project.pbxproj").file? && marker.file? && marker.read == checksum

    environment = {}
    unless system(@environment, "ruby", "-e", "require 'xcodeproj'", out: File::NULL, err: File::NULL)
      executable = Pathname.new(executable!("xcodeproj")).realpath
      gem_home = executable.dirname.parent.join("libexec")
      raise Error, "Unable to locate the CocoaPods Ruby environment" unless gem_home.join("gems").directory?
      environment["GEM_HOME"] = gem_home.to_s
    end
    run!("ruby", generator, environment: environment)
    marker.write(checksum)
  end

  def verify_ios
    %w[legacy new].each do |architecture|
      project = @consumer.join("ios-#{architecture}")
      sync(@consumer.join("ios"), project, exclude: IOS_GENERATED)
      create_ios_project(project)
      flags = @ios_flags.fetch(architecture)
      environment = flags.merge("SFIORA_REACT_NATIVE_PATH" => @rn.to_s, "SFIORA_PACKAGE_PATH" => @package.to_s,
        "RCT_NEW_ARCH_ENABLED" => architecture == "legacy" ? "0" : "1")
      puts "Verifying RN iOS #{architecture}: #{flags.map { |key, value| "#{key}=#{value}" }.join(' ')}"
      run!("pod", "install", chdir: project, environment: environment, log: "pods-#{architecture}.log")
      self.class.verify_pods!(project, @rn_version, flags)
      %w[device simulator].each do |sdk|
        platform = sdk == "device" ? "iOS" : "iOS Simulator"
        run!("xcodebuild", "-workspace", project.join("SfioraConsumer.xcworkspace"),
          "-scheme", architecture == "legacy" ? "SfioraConsumer" : "SfioraReactNative", "-configuration", "Debug",
          "-destination", "generic/platform=#{platform}", "-derivedDataPath", @work.join("DerivedData", architecture),
          "CODE_SIGNING_ALLOWED=NO", "build", environment: environment, log: "ios-#{architecture}-#{sdk}.log")
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    $stdout.sync = true
    raise ReactNativeVerification::Error, "Usage: #{$PROGRAM_NAME}" unless ARGV.empty?
    ReactNativeVerification.new.run
  rescue ReactNativeVerification::Error, KeyError, JSON::ParserError, Psych::Exception, SystemCallError => error
    warn error.message
    exit 1
  end
end
