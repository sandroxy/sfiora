require "minitest/autorun"
require "fileutils"
require_relative "verify-maven-signatures"

class MavenSignaturesTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("sfiora-maven-test-")
    @repository = File.join(@temporary, "repository.zip")
    @signer = "A" * 40
    @reported_signer = @signer
    @files = {}
    @payloads = %w[sfiora sfiora-ui].flat_map do |name|
      [".aar", ".pom", ".module", "-sources.jar", "-javadoc.jar"].map do |suffix|
        "io/github/sandroxy/#{name}/1.0.0/#{name}-1.0.0#{suffix}"
      end
    end
    @payloads.each do |path|
      set_file(path, path + " fixture\n")
      set_file(path + ".asc", "signature fixture\n")
    end
    @aars = %w[sfiora sfiora-ui].to_h do |name|
      path = File.join(@temporary, "#{name}.aar")
      File.binwrite(path, @files.fetch("io/github/sandroxy/#{name}/1.0.0/#{name}-1.0.0.aar"))
      [name, path]
    end
    @verified = []
  end

  def teardown
    if @gpg_home
      Open3.capture3("gpgconf", "--homedir", @gpg_home, "--kill", "all")
      FileUtils.remove_entry(@gpg_home)
    end
    FileUtils.remove_entry(@temporary)
  end

  def set_file(path, content)
    @files[path] = content
    MavenSignatures::HASHES.each { |name, type| @files[path + "." + name] = type.hexdigest(content) }
  end

  def archive
    input = File.join(@temporary, "files")
    @files.each do |path, content|
      destination = File.join(input, path)
      FileUtils.mkdir_p(File.dirname(destination))
      File.binwrite(destination, content)
    end
    File.delete(@repository) if File.exist?(@repository)
    _output, error, status = Open3.capture3("zip", "-q", "-X", @repository, "-@",
      chdir: input, stdin_data: @files.keys.sort.join("\n") + "\n")
    assert status.success?, error
  end

  def verify(real_gpg: false)
    archive
    original = MavenSignatures.method(:command)
    inspection = lambda do |*arguments|
      if arguments.first == "gpg"
        @verified << arguments
        assert_includes arguments, "--no-auto-key-retrieve"
        if real_gpg
          original.call("gpg", "--homedir", @gpg_home, *arguments.drop(1))
        else
          "[GNUPG:] VALIDSIG #{@reported_signer} 2026-01-01 1 0 4 0 22 8 00 #{@reported_signer}\n"
        end
      else
        original.call(*arguments)
      end
    end
    MavenSignatures.stub(:command, inspection) do
      MavenSignatures.verify!(repository: @repository, aars: @aars, version: "1.0.0", signer: @signer)
    end
  end

  def test_all_core_and_ui_payloads_and_signatures_are_checked
    verify
    assert_equal 10, @verified.length
  end

  def test_wrong_signer_or_missing_explicit_fingerprint_is_rejected
    @reported_signer = "B" * 40
    assert_match(/selected key/, assert_raises(MavenSignatures::Error) { verify }.message)
    @signer = nil
    assert_match(/explicit signing fingerprint/, assert_raises(MavenSignatures::Error) { verify }.message)
  end

  def test_missing_signatures_and_extra_files_are_rejected
    signature = @payloads.first + ".asc"
    original = @files.delete(signature)
    assert_raises(MavenSignatures::Error) { verify }
    @files[signature] = original
    @files["unexpected.txt"] = "extra"
    assert_raises(MavenSignatures::Error) { verify }
  end

  def test_payload_and_signature_checksums_are_checked
    path = @payloads.first
    @files[path + ".sha256"] = "f" * 64
    assert_match(/sha256 mismatch/, assert_raises(MavenSignatures::Error) { verify }.message)
    set_file(path, @files.fetch(path))
    @files[path + ".asc.sha512"] = "f" * 128
    assert_match(/sha512 mismatch/, assert_raises(MavenSignatures::Error) { verify }.message)
  end

  def test_standalone_ui_cannot_differ_from_signed_maven_bytes
    File.binwrite(@aars.fetch("sfiora-ui"), "replaced UI")
    assert_match(/Standalone sfiora-ui/, assert_raises(MavenSignatures::Error) { verify }.message)
  end

  def test_real_signatures_reject_tampering_even_with_updated_checksums
    @gpg_home = Dir.mktmpdir("sfiora-crypto-", "/tmp")
    command = lambda do |*arguments|
      output, error, status = Open3.capture3("gpg", "--homedir", @gpg_home, "--batch", "--pinentry-mode", "loopback",
        "--passphrase", "", *arguments)
      assert status.success?, error
      output
    end
    command.call("--quick-generate-key", "Sfiora Fixture <fixture@example.invalid>", "ed25519", "sign", "0")
    @signer = command.call("--with-colons", "--list-keys").lines.map { |line| line.split(":") }
      .find { |fields| fields.first == "fpr" }.fetch(9)
    @payloads.each do |path|
      input = File.join(@temporary, File.basename(path))
      File.binwrite(input, @files.fetch(path))
      command.call("--armor", "--detach-sign", input)
      set_file(path + ".asc", File.binread(input + ".asc"))
    end
    verify(real_gpg: true)
    path = @payloads.find { |entry| entry.end_with?("sfiora-ui-1.0.0.pom") }
    set_file(path, "changed metadata with valid checksum sidecars")
    assert_raises(MavenSignatures::Error) { verify(real_gpg: true) }
  end
end
