#!/usr/bin/env ruby
require "digest"
require "json"
require "net/http"
require "open3"
require "optparse"
require "pathname"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: publish-accepted.rb --candidate FILE --acceptance FILE --channel github|npm|maven|uniapp"
  parser.on("--candidate FILE") { |value| options[:candidate] = value }
  parser.on("--acceptance FILE") { |value| options[:acceptance] = value }
  parser.on("--channel NAME") { |value| options[:channel] = value }
  parser.on("-h", "--help") { puts parser; exit }
end.parse!
abort("All three options are required") unless %i[candidate acceptance channel].all? { |key| options[key] }
abort("Unexpected arguments") unless ARGV.empty?
abort("Unknown publication channel") unless %w[github npm maven uniapp].include?(options[:channel])
root = File.expand_path("..", __dir__)
gate_arguments = [
  "ruby", "#{__dir__}/verify-publish-candidate.rb", "--candidate", options[:candidate],
  "--acceptance", options[:acceptance]
]
gate, status = Open3.capture2e(*gate_arguments)
abort(gate) unless status.success?
candidate_path = Pathname.new(options[:candidate]).realpath
candidate = JSON.parse(candidate_path.read)
version = candidate.fetch("version")
artifacts = candidate.fetch("artifacts").to_h do |entry|
  [entry.fetch("role"), candidate_path.parent.join(entry.fetch("file")).to_s]
end
run = lambda do |*args|
  abort("Publication command failed") unless system(*args, chdir: root)
end
case options[:channel]
when "github"
  run.call("gh", "release", "create", version, *artifacts.values,
    "--repo", "sandroxy/sfiora", "--verify-tag", "--title", "Sfiora #{version}",
    "--notes", "Accepted candidate #{candidate.fetch("candidateId")}. See the included artifact hashes and Sfiora release documentation.")
when "npm"
  run.call("npm", "publish", artifacts.fetch("react-native-package"), "--access", "public",
    "--ignore-scripts", "--registry", "https://registry.npmjs.org")
when "maven"
  token = ENV.fetch("SFIORA_CENTRAL_TOKEN") { abort("SFIORA_CENTRAL_TOKEN is required") }
  abort("Invalid Central token") if token.empty? || token.match?(/[\r\n]/)
  archive = artifacts.fetch("native-android-maven-repository")
  uri = URI("https://central.sonatype.com/api/v1/publisher/upload?publishingType=USER_MANAGED")
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{token}"
  File.open(archive, "rb") do |file|
    request.set_form([["bundle", file]], "multipart/form-data")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 120) do |http|
      http.request(request)
    end
    abort("Central upload returned HTTP #{response.code}; inspect the portal before retrying") unless response.code == "201"
    deployment = response.body.strip
    abort("Central returned an unexpected deployment response; inspect the portal before retrying") unless deployment.match?(/\A[0-9a-f-]{36}\z/i)
    puts "Central deployment #{deployment} uploaded for validation. Publish these same bytes in the Central portal after validation."
  end
when "uniapp"
  puts "Accepted UTS archive: #{artifacts.fetch('uniapp-uts-package')}"
  puts "In the accepted artifact-only consumer project, right-click uni_modules/Sandrox-Sfiora in HBuilderX and choose 发布到插件市场."
  puts "Publish the verified module from this archive, including its packaged readme.md, without rebuilding or repacking."
  puts "Legacy compatibility/offline archive: #{artifacts.fetch('uniapp-legacy-package')}"
end
