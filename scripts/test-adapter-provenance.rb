#!/usr/bin/env ruby
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

verifier = File.expand_path("verify-adapter-provenance.rb", __dir__)
Dir.mktmpdir("sfiora-provenance-test-") do |root|
  write = lambda do |path, bytes|
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
  end
  run = lambda do |*args, chdir: root|
    output, status = Open3.capture2e(*args, chdir: chdir)
    raise output unless status.success?
  end
  # These are deliberately text fixtures, not build outputs or acceptance evidence.
  %w[sfiora sfiora-ui].each { |name| write.call("#{root}/dist/native-android/#{name}-1.0.0.aar", "#{name} fixture") }
  core_files = {
    "Sfiora.xcframework/Info.plist" => "fixture plist",
    "Sfiora.xcframework/ios-arm64/Sfiora.framework/Sfiora" => "device fixture",
    "Sfiora.xcframework/ios-arm64-simulator/Sfiora.framework/Sfiora" => "simulator fixture",
  }
  core_files.each { |path, bytes| write.call("#{root}/core/#{path}", bytes) }
  ios = "#{root}/dist/native-ios/sfiora-1.0.0.xcframework.zip"
  FileUtils.mkdir_p(File.dirname(ios))
  run.call("zip", "-qr", ios, "Sfiora.xcframework", chdir: "#{root}/core")
  archives = []
  %w[rn legacy uts].each do |kind|
    prefix = {"rn" => "package", "legacy" => "Sandrox-Sfiora", "uts" => ""}.fetch(kind)
    package = File.join(root, kind, prefix)
    android_dir = {"rn" => "android/libs", "legacy" => "android", "uts" => "utssdk/app-android/libs"}.fetch(kind)
    ios_dir = {"rn" => "ios/Frameworks", "legacy" => "ios", "uts" => "utssdk/app-ios/Frameworks"}.fetch(kind)
    names = %w[sfiora sfiora-ui sfiora-bridge-support]
    names << "sfiora-uniapp" if kind == "legacy"
    android_hashes = {}
    names.each do |name|
      filename = if kind == "legacy"
                   {"sfiora" => "Sfiora-1.0.0", "sfiora-ui" => "SfioraUI-1.0.0",
                    "sfiora-bridge-support" => "SfioraBridgeSupport", "sfiora-uniapp" => "SfioraUniApp"}.fetch(name)
                 else name
                 end
      bytes = "#{name} fixture"
      write.call("#{package}/#{android_dir}/#{filename}.aar", bytes)
      android_hashes["#{name}.aar"] = Digest::SHA256.hexdigest(bytes)
    end
    core_files.each do |path, bytes|
      if kind == "rn"
        write.call("#{package}/#{ios_dir}/#{path}", bytes)
      elsif path.include?("/ios-arm64/")
        write.call("#{package}/#{ios_dir}/Sfiora.framework/Sfiora", bytes)
      end
    end
    identity = if kind == "rn"
                 {"name" => "@sandrox/sfiora"}
               else
                 {"id" => "Sandrox-Sfiora"}.merge(kind == "legacy" ? {"_dp_type" => "nativeplugin"} : {"dcloudext" => {"type" => "uts"}})
               end
    write.call("#{package}/package.json", JSON.generate(identity.merge("version" => "1.0.0")))
    write.call("#{package}/sfiora-artifacts.json", JSON.generate({
      schemaVersion: 1, version: "1.0.0", nativeArtifacts: {
        android: android_hashes, ios: {"sfiora.xcframework.zip" => Digest::SHA256.file(ios).hexdigest}
      }
    }))
    archive = "#{root}/#{kind}.#{kind == "rn" ? "tgz" : "zip"}"
    if kind == "rn"
      run.call("tar", "-czf", archive, prefix, chdir: "#{root}/#{kind}")
    else
      run.call("zip", "-qr", archive, ".", chdir: "#{root}/#{kind}")
    end
    archives << archive
  end
  run.call("ruby", verifier, root, "1.0.0", *archives)
  write.call("#{root}/uts/utssdk/app-android/libs/sfiora.aar", "substituted core")
  provenance_path = "#{root}/uts/sfiora-artifacts.json"
  provenance = JSON.parse(File.read(provenance_path))
  provenance["nativeArtifacts"]["android"]["sfiora.aar"] = Digest::SHA256.hexdigest("substituted core")
  write.call(provenance_path, JSON.generate(provenance))
  run.call("zip", "-qr", archives.last, ".", chdir: "#{root}/uts")
  output, status = Open3.capture2e("ruby", verifier, root, "1.0.0", *archives)
  raise "A self-consistent adapter with different core bytes was accepted: #{output}" if status.success?
  raise output unless output.include?("Embedded Android core differs")
end
puts "Verified adapter archives against actual core bytes, including a re-hashed substitution."
