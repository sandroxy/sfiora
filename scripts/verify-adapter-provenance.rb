#!/usr/bin/env ruby
require "digest"
require "json"
require "open3"

abort("Usage: #{$PROGRAM_NAME} ROOT VERSION RN_TGZ LEGACY_ZIP UTS_ZIP") unless ARGV.length == 5
root, version, rn, legacy, uts = ARGV
read_entry = lambda do |archive, entry|
  command = archive.end_with?(".tgz") ? ["tar", "-xOf", archive, entry] : ["unzip", "-p", archive, entry]
  value, error, status = Open3.capture3(*command)
  abort("Unable to read #{entry} from #{archive}: #{error}") unless status.success?
  value.b
end
ios = "#{root}/dist/native-ios/sfiora-#{version}.xcframework.zip"
listing, status = Open3.capture2("unzip", "-Z1", ios)
abort("Unable to list native iOS artifact") unless status.success?
ios_entries = listing.lines.map(&:chomp).reject { |name| name.end_with?("/") }
abort("Invalid native iOS archive") if ios_entries.empty? || ios_entries.uniq != ios_entries
device_prefix = "Sfiora.xcframework/ios-arm64/Sfiora.framework/"
packages = [
  [rn, "package", "android/libs", "ios/Frameworks", true],
  [legacy, "Sandrox-Sfiora", "android", "ios", false],
  [uts, "", "utssdk/app-android/libs", "utssdk/app-ios/Frameworks", false],
]
packages.each do |archive, prefix, android_dir, ios_dir, whole_framework|
  metadata = JSON.parse(read_entry.call(archive, [prefix, "package.json"].reject(&:empty?).join("/")))
  valid_identity = if archive == rn
                     metadata["name"] == "@sandrox/sfiora"
                   elsif archive == legacy
                     metadata["id"] == "Sandrox-Sfiora" && metadata["_dp_type"] == "nativeplugin"
                   else
                     metadata["id"] == "Sandrox-Sfiora" && metadata.dig("dcloudext", "type") == "uts"
                   end
  abort("Adapter package identity differs") unless valid_identity && metadata["version"] == version
  provenance = JSON.parse(read_entry.call(archive, [prefix, "sfiora-artifacts.json"].reject(&:empty?).join("/")))
  abort("Adapter provenance identity differs") unless provenance["schemaVersion"] == 1 && provenance["version"] == version
  android_names = if archive == legacy
                    {"sfiora" => "Sfiora-#{version}", "sfiora-ui" => "SfioraUI-#{version}",
                     "sfiora-bridge-support" => "SfioraBridgeSupport", "sfiora-uniapp" => "SfioraUniApp"}
                  else
                    %w[sfiora sfiora-ui sfiora-bridge-support].to_h { |name| [name, name] }
                  end
  android_names.each do |name, packaged_name|
    bytes = read_entry.call(archive, [prefix, android_dir, "#{packaged_name}.aar"].reject(&:empty?).join("/"))
    digest = Digest::SHA256.hexdigest(bytes)
    abort("Embedded Android provenance differs: #{name}") unless
      provenance.dig("nativeArtifacts", "android", "#{name}.aar") == digest
    if %w[sfiora sfiora-ui].include?(name)
      abort("Embedded Android core differs: #{name}") unless
        bytes == File.binread("#{root}/dist/native-android/#{name}-#{version}.aar")
    end
  end
  abort("Adapter iOS provenance differs") unless
    provenance.dig("nativeArtifacts", "ios", "sfiora.xcframework.zip") == Digest::SHA256.file(ios).hexdigest
  selected = whole_framework ? ios_entries : ios_entries.select { |entry| entry.start_with?(device_prefix) }
  abort("Native iOS framework is missing") if selected.empty?
  selected.each do |entry|
    packaged = whole_framework ? entry : "Sfiora.framework/#{entry.delete_prefix(device_prefix)}"
    abort("Embedded iOS core differs: #{packaged}") unless
      read_entry.call(ios, entry) == read_entry.call(archive, [prefix, ios_dir, packaged].reject(&:empty?).join("/"))
  end
end
puts "Verified the actual native bytes embedded in every adapter."
