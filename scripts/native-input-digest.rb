#!/usr/bin/env ruby
require "digest"
require "open3"
require "pathname"

module NativeInputDigest
  INPUTS = %w[LICENSE plugin.json native/ios scripts/package-native-ios.sh scripts/release-common.sh scripts/native-input-digest.rb].freeze
  module_function

  def digest(root, commit = nil)
    git = lambda do |*args|
      output, error, status = Open3.capture3("git", "-C", root.to_s, *args)
      raise error unless status.success?
      output
    end
    entries = if commit
                git.call("ls-tree", "-rz", "--full-tree", commit, "--", *INPUTS).split("\0").map do |entry|
                  metadata, path = entry.split("\t", 2)
                  mode, type, object = metadata.split(" ")
                  raise "Unsupported source input: #{path}" unless type == "blob" && %w[100644 100755].include?(mode)
                  [path, mode, git.call("cat-file", "blob", object)]
                end
              else
                git.call("ls-files", "-cz", "--others", "--exclude-standard", "--", *INPUTS).split("\0").uniq.map do |path|
                  file = Pathname.new(root).join(path)
                  raise "Source input must be a regular file: #{path}" unless file.file? && !file.symlink?
                  [path, file.executable? ? "100755" : "100644", file.binread]
                end
              end
    raise "No native iOS inputs" if entries.empty?
    Digest::SHA256.hexdigest(entries.sort_by(&:first).map do |path, mode, bytes|
      [path, mode, Digest::SHA256.hexdigest(bytes)].join("\0") + "\n"
    end.join)
  end
end

if $PROGRAM_NAME == __FILE__
  abort("Usage: #{$PROGRAM_NAME} [COMMIT]") unless ARGV.length <= 1
  puts NativeInputDigest.digest(File.expand_path("..", __dir__), ARGV.first)
end
