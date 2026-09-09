#!/usr/bin/env ruby
require "json"
require "open3"
require "optparse"
require "pathname"
require "shellwords"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: publish-accepted.rb --candidate FILE --acceptance FILE --channel github|npm|maven|uniapp [--source DIR]"
  parser.separator "Verifies the accepted files and prints manual publication steps; never uploads or publishes."
  parser.on("--candidate FILE") { |value| options[:candidate] = value }
  parser.on("--acceptance FILE") { |value| options[:acceptance] = value }
  parser.on("--channel NAME") { |value| options[:channel] = value }
  parser.on("--source DIR", "Clean checkout of the accepted release tag") { |value| options[:source] = value }
  parser.on("-h", "--help") { puts parser; exit }
end.parse!
abort("All three options are required") unless %i[candidate acceptance channel].all? { |key| options[key] }
abort("Unexpected arguments") unless ARGV.empty?
abort("Unknown publication channel") unless %w[github npm maven uniapp].include?(options[:channel])
gate_arguments = [
  RbConfig.ruby, "#{__dir__}/verify-publish-candidate.rb", "--candidate", options[:candidate],
  "--acceptance", options[:acceptance]
]
gate_arguments.concat(["--source", options[:source]]) if options[:source]
gate, status = Open3.capture2e(*gate_arguments)
abort(gate) unless status.success?
candidate_path = Pathname.new(options[:candidate]).realpath
candidate = JSON.parse(candidate_path.read)
version = candidate.fetch("version")
artifacts = candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
path = ->(role) { candidate_path.parent.join(artifacts.fetch(role).fetch("file")).to_s }
puts "Verified #{candidate.fetch('candidateId')}. Instructions only; nothing was uploaded or published."

case options[:channel]
when "github"
  puts "In https://github.com/sandroxy/sfiora/releases select the existing tag #{version}."
  puts "Title: Sfiora #{version}. Use a short summary and link to the tag's CHANGELOG.md."
  puts "Attach only these initial GitHub Release files:"
  %w[native-ios-xcframework native-build-manifest react-native-package checksum-react-native-package
     uniapp-legacy-package checksum-uniapp-legacy-package uniapp-uts-package checksum-uniapp-uts-package].each do |role|
    puts path.call(role)
  end
  puts "Android AARs and their sidecars are added later by Mirror Android AAR, from published Maven Central bytes."
  puts "The Maven ZIP belongs in Central Portal; other candidate checksums remain local acceptance evidence."
when "maven"
  puts "In https://central.sonatype.com/publishing upload this signed Central bundle in user-managed mode:"
  puts path.call("native-android-maven-repository")
  puts "Deployment Name: sfiora-#{version}. Publish after portal validation."
  puts "It contains both io.github.sandroxy:sfiora:#{version} and io.github.sandroxy:sfiora-ui:#{version}."
  puts "Once both coordinates are publicly available, run GitHub Actions > Mirror Android AAR with version=#{version}."
  puts "Run the workflow from the updated default branch; it reads the existing release tag and never rebuilds."
when "npm"
  puts "After GitHub Release and Maven Central are public, use GitHub Actions > Publish npm with version=#{version}."
  puts "Trusted publisher: GitHub Actions, owner=sandroxy, repository=sfiora, workflow=publish-npm.yml, allow npm publish."
  puts "Run from the updated default branch. The workflow verifies and publishes the accepted Release tarball through OIDC."
  puts "If this new package has no npm settings page yet, first publish this same accepted tarball with your existing interactive npm login:"
  puts Shellwords.join(["npm", "publish", path.call("react-native-package"), "--access", "public", "--ignore-scripts", "--registry", "https://registry.npmjs.org/"])
  puts "Then configure its trusted publisher for later versions. Never publish a placeholder or republish this version."
when "uniapp"
  puts "Accepted UTS archive: #{path.call('uniapp-uts-package')}"
  puts "In the accepted artifact-only consumer project, right-click uni_modules/Sandrox-Sfiora in HBuilderX and choose 发布到插件市场."
  puts "Publish the verified module, including packaged readme.md, without rebuilding or repacking."
  puts "Legacy compatibility/offline archive: #{path.call('uniapp-legacy-package')}"
  puts "For the GitHub mirrors run Verify UniApp Release Assets with version=#{version},"
  puts "uts_sha256=#{artifacts.fetch('uniapp-uts-package').fetch('sha256')} and"
  puts "legacy_sha256=#{artifacts.fetch('uniapp-legacy-package').fetch('sha256')}."
  puts "Verify the Marketplace installation separately; HBuilderX may normalize publication metadata."
end
