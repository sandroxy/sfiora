#!/usr/bin/env ruby
require "json"
require "net/http"
require "uri"

abort("Usage: #{$PROGRAM_NAME}") unless ARGV.empty?
manifest = JSON.parse(File.read(File.expand_path("../plugin.json", __dir__)))
version = manifest.fetch("version")
package = URI.encode_www_form_component(manifest.fetch("adapters").fetch("reactNative").fetch("package"))
urls = ["https://registry.npmjs.org/#{package}/#{version}"]
android = manifest.fetch("native").fetch("android")
android.fetch("artifacts").each do |artifact|
  urls << "https://repo.maven.apache.org/maven2/#{android.fetch("group").tr(".", "/")}/#{artifact}/#{version}/#{artifact}-#{version}.pom"
end
urls.each do |url|
  uri = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 15) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
  abort("Version #{version} already exists: #{uri.host}#{uri.path}") if response.is_a?(Net::HTTPSuccess)
  abort("Unable to confirm version availability: HTTP #{response.code} from #{uri.host}") unless response.code == "404"
end
puts "Sfiora #{version} is absent from the npm and Maven public channels."
