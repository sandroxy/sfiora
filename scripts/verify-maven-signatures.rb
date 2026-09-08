require "digest"
require "open3"
require "tmpdir"

module MavenSignatures
  class Error < StandardError; end
  HASHES = {"md5" => Digest::MD5, "sha1" => Digest::SHA1, "sha256" => Digest::SHA256, "sha512" => Digest::SHA512}.freeze
  module_function

  def command(*arguments)
    output, error, status = Open3.capture3(*arguments.map(&:to_s))
    raise Error, "Maven signature verification failed: #{error.strip}" unless status.success?
    output
  end

  def verify!(repository:, aars:, version:, signer:)
    raise Error, "An explicit signing fingerprint is required" unless
      signer.is_a?(String) && signer.match?(/\A(?:[0-9A-F]{40}|[0-9A-F]{64})\z/)
    raise Error, "Unexpected Maven version or artifacts" unless
      version.is_a?(String) && version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/) &&
        aars.keys.sort == %w[sfiora sfiora-ui]
    payloads = aars.keys.sort.flat_map do |name|
      prefix = "io/github/sandroxy/#{name}/#{version}/#{name}-#{version}"
      [".aar", ".pom", ".module", "-sources.jar", "-javadoc.jar"].map { |suffix| prefix + suffix }
    end
    expected = payloads.flat_map do |path|
      [path, path + ".asc"].flat_map { |name| [name] + HASHES.keys.map { |hash| name + "." + hash } }
    end.sort
    entries = command("unzip", "-Z1", repository).lines.map(&:chomp)
    raise Error, "Maven archive contains unexpected, duplicate or unsafe entries" unless entries.sort == expected
    Dir.mktmpdir("sfiora-maven-signatures-") do |directory|
      payloads.each do |path|
        [path, path + ".asc"].each do |entry|
          content = command("unzip", "-p", repository, entry)
          File.binwrite(File.join(directory, File.basename(entry)), content)
          HASHES.each do |algorithm, type|
            recorded = command("unzip", "-p", repository, entry + "." + algorithm).strip
            raise Error, "Maven #{algorithm} mismatch: #{entry}" unless recorded == type.hexdigest(content)
          end
        end
        payload = File.join(directory, File.basename(path))
        output = command("gpg", "--batch", "--no-auto-key-retrieve", "--no-auto-check-trustdb",
          "--status-fd", "1", "--verify", payload + ".asc", payload)
        signatures = output.lines.map(&:split).select { |fields| fields[0, 2] == ["[GNUPG:]", "VALIDSIG"] }
        raise Error, "Maven signature does not match the selected key: #{path}" unless signatures.length == 1 &&
          [signatures.first[2], signatures.first[11]].include?(signer)
      end
      aars.each do |name, path|
        raise Error, "Standalone #{name} AAR differs from signed Maven bytes" unless
          File.binread(path) == File.binread(File.join(directory, "#{name}-#{version}.aar"))
      end
    end
  end
end
