#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "set"
require "uri"

# Local consistency checks, not a substitute for compiling examples or
# reviewing their behavior. No network requests or package builds are made.
class DocumentationVerification
  attr_reader :errors

  def initialize(root = Pathname.new(__dir__).parent)
    @root = Pathname.new(root).expand_path
    @errors = []
  end

  def read(path)
    @root.join(path).read
  end

  def require_text(path, text)
    errors << "#{path}: missing documented value #{text.inspect}" unless read(path).include?(text)
  end

  def require_row(path, label, values)
    row = read(path).lines.find { |line| line.start_with?("| #{label} |") }
    values.each do |value|
      errors << "#{path}: #{label} row must declare #{value.inspect}" unless row && row.include?(value)
    end
  end

  def check_links(path, contents)
    # Code fences contain example paths and placeholder commands, not links.
    prose = contents.gsub(/^```[^\n]*\n.*?^```[^\n]*$/m, "")
    links = prose.scan(/\[[^\]\n]*\]\(<?([^\s)>]+)>?(?:\s+"[^"]*")?\)/).flatten
    links.concat(prose.scan(/<(?:img|a)\b[^>]*\b(?:src|href)=["']([^"']+)["']/).flatten)
    links.each do |link|
      next if link.start_with?("#", "//") || link.match?(/\A[a-z][a-z0-9+.-]*:/i)

      relative = URI::DEFAULT_PARSER.unescape(link.split(/[?#]/, 2).first)
      target = @root.join(path).dirname.join(relative).cleanpath
      unless target.to_s.start_with?(@root.to_s + File::SEPARATOR) && target.exist?
        errors << "#{path}: missing or nonportable local link #{link}"
      end
    end
  end

  def check_example_methods(path, declaration)
    methods = read(declaration).scan(/^export (?:declare )?function (\w+)[(<]/).flatten.to_set
    if methods.empty?
      errors << "#{declaration}: no public function declarations found"
      return
    end

    blocks = read(path).scan(/^```(?:js|ts|javascript|typescript|uts)\n(.*?)^```/m).flatten
    blocks.each do |block|
      block.scan(/\bsfiora\.(\w+)\s*\(/).flatten.each do |method|
        errors << "#{path}: example calls undeclared method sfiora.#{method}" unless methods.include?(method)
      end
    end
  end

  def check_landing_pages
    paths = %w[README.md README-EN.md]
    manifest = JSON.parse(read("plugin.json"))
    android = manifest.fetch("native").fetch("android")
    ios = manifest.fetch("native").fetch("ios").fetch("minimumVersion").sub(/\.0\z/, "")
    adapters = manifest.fetch("adapters")
    package = adapters.fetch("reactNative").fetch("package")
    marketplace = "https://ext.dcloud.net.cn/plugin?name=#{adapters.fetch('uniAppUts').fetch('id')}"
    uts = JSON.parse(read("uni_modules/Sandrox-Sfiora/package.json"))
    x_app = uts.fetch("uni_modules").fetch("platforms").fetch("client").fetch("uni-app-x").fetch("app")
    guides = %w[native/android/README.md native/ios/README.md adapters/react-native/README.md
                adapters/uniapp/README.md DEVELOPMENT.md RELEASING.md CHANGELOG.md SECURITY.md]
    channels = ["https://central.sonatype.com/artifact/#{android.fetch('group')}/sfiora",
                "https://github.com/sandroxy/sfiora", "https://www.npmjs.com/package/#{package}",
                marketplace, "https://github.com/sandroxy/sfiora/releases"]

    paths.each do |path|
      (guides + channels).each { |target| require_text(path, "](#{target})") }
      # Landing tables help readers choose a channel and guide. Check version
      # requirements in the platform guides, where the host distinctions belong.
      require_row(path, "Android", ["](#{channels[0]})", "](native/android/README.md)"])
      require_row(path, "iOS", ["](#{channels[1]})", "](native/ios/README.md)"])
      require_row(path, "React Native / Expo", ["](#{channels[2]})", "](adapters/react-native/README.md)"])
      require_row(path, "UniApp", ["](#{marketplace})", "](adapters/uniapp/README.md)"])
    end
    require_text("native/android/README.md", "Requires Android API #{android.fetch('minimumSdk')}")
    require_text("native/ios/README.md", "Requires iOS #{ios}")
    require_text("adapters/uniapp/README.md", "](#{marketplace})")
    %w[sfiora-uniapp-<version>.zip sfiora-uniapp-legacy-<version>.zip].each do |name|
      require_text("adapters/uniapp/README.md", "`#{name}`")
    end

    rn = JSON.parse(read("adapters/react-native/package.json"))
    rn_minimum = rn.fetch("peerDependencies").fetch("react-native").delete_prefix(">=").sub(/\.0\z/, "")
    node_minimum = rn.fetch("engines").fetch("node").delete_prefix(">=").sub(/\.0(?:\.0)?\z/, "")
    require_text("adapters/react-native/README.md", "React Native #{rn_minimum}+")
    require_text("adapters/react-native/README.md", "Node.js #{node_minimum}+")

    %w[legacy UTS].each do |kind|
      adapter = kind == "legacy" ? "uniApp" : "uniAppUts"
      require_text("adapters/uniapp/README.md", "HBuilderX #{adapters.fetch(adapter).fetch('minimumHBuilderX')}")
      require_row("adapters/uniapp/README.md", "经典 uni-app #{kind}",
                  ["Android API #{android.fetch('minimumSdk')}", "iOS #{ios}"])
    end
    require_row("adapters/uniapp/README.md", "uni-app x",
                ["Android API #{x_app.fetch('android').fetch('minVersion')}",
                 "iOS #{x_app.fetch('ios').fetch('minVersion')}"])
  end

  def run
    files, status = Open3.capture2("git", "-C", @root.to_s, "ls-files", "--cached", "--others",
                                  "--exclude-standard", "-z", "--", "*.md")
    abort "Unable to enumerate repository documentation" unless status.success?

    files.split("\0").uniq.each do |path|
      next unless @root.join(path).file? # A tracked document may have been removed in this change.

      check_links(path, read(path))
    end
    check_landing_pages
    check_example_methods("adapters/react-native/README.md", "adapters/react-native/index.d.ts")
    check_example_methods("adapters/uniapp/README.md", "adapters/uniapp/index.d.ts")
    abort errors.join("\n") unless errors.empty?

    puts "Sfiora documentation links, requirements, and bridge examples passed."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: ruby scripts/verify-documentation.rb" unless ARGV.empty?
  DocumentationVerification.new.run
end
