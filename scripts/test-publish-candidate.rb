#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "time"
require_relative "native-release-manifest"

class PublishCandidateTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("sfiora-publish-candidate-")
    @root = Pathname.new(@temporary)
    @product = @root.join("product")
    @product.join("scripts").mkpath
    source = Pathname.new(__dir__).parent
    %w[snapshot-release-candidate.rb verify-publish-candidate.rb publish-accepted.rb release-policy.rb native-release-manifest.rb
       native-artifact-reuse.rb native-input-digest.rb git-input-digest.rb].each do |file|
      FileUtils.cp(source.join("scripts", file), @product.join("scripts", file))
    end
    %w[release-policy.json native-reuse-policy.json].each do |file|
      FileUtils.cp(source.join(file), @product.join(file))
    end
    @policy = ReleasePolicy.load(@product.join("release-policy.json"))
    @product.join("plugin.json").write(JSON.generate("id" => "sfiora", "version" => "1.0.0"))
    NativeInputDigest::INPUTS.each do |scope|
      path = @product.join(scope)
      path = path.join("input.txt") if source.join(scope).directory?
      path.parent.mkpath
      path.write("fixture input\n") unless path.file?
    end
    package = source.join("Package.swift").read.sub(/let sfioraBinaryChecksum =\s*"[0-9a-f]+"/,
      "let sfioraBinaryChecksum = \"#{Digest::SHA256.hexdigest("native-ios-xcframework\n")}\"")
    @product.join("Package.swift").write(package)
    # Exercise the actual publication gate with synthetic artifacts, without native compilation.
    @product.join("scripts/verify-ios-xcframework-provenance.sh").write("#!/bin/sh\nexit 0\n")
    @product.join(".gitignore").write("/dist/\n")
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    git("config", "tag.gpgsign", "false")
    git("add", ".")
    git("commit", "-qm", "fixture")
    @commit = git("rev-parse", "HEAD").strip
    git("tag", "-a", "1.0.0", "-m", "fixture")

    @candidate_root = @product.join("dist")
    qualifications = @policy.fetch("qualifications").to_h { |key| [key, true] }
    roles = ReleasePolicy.expected_artifact_roles(@policy, qualifications)
    contents = roles.to_h { |role| [role, role + "\n"] }
    native_paths = NativeReleaseManifest.paths("1.0.0")
    native_manifest = {
      "schemaVersion" => 2, "plugin" => "sfiora", "version" => "1.0.0", "commit" => @commit,
      "dirty" => false, "androidMavenSigned" => true,
      "iosBinarySourceCommit" => @commit, "iosBinaryPromoted" => true,
      "artifacts" => native_paths.map do |role, path|
        content = contents.fetch(role)
        {"file" => path, "bytes" => content.bytesize, "sha256" => Digest::SHA256.hexdigest(content)}
      end,
    }
    contents["native-build-manifest"] = JSON.pretty_generate(native_manifest) + "\n"
    entries = contents.map do |role, content|
      primary = role.delete_prefix("checksum-")
      filename = native_paths.key?(primary) ? File.basename(native_paths.fetch(primary)) : primary
      filename += ".sha256" if role.start_with?("checksum-")
      path = @candidate_root.join("artifacts", filename)
      path.parent.mkpath
      path.binwrite(content)
      {"role" => role, "file" => "artifacts/#{filename}", "bytes" => path.size,
       "sha256" => Digest::SHA256.file(path).hexdigest}
    end
    set_payload = entries.sort_by { |entry| entry.fetch("role") }.map do |entry|
      %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
    end.join
    digest = Digest::SHA256.hexdigest(set_payload)
    @candidate = {
      "schemaVersion" => @policy.fetch("candidateSchemaVersion"), "kind" => "plugin-release-candidate",
      "state" => "candidate", "acceptanceEligible" => true, "plugin" => "sfiora", "version" => "1.0.0",
      "candidateId" => "sfiora-1.0.0-#{@commit[0, 12]}-#{digest[0, 12]}", "artifactSetSha256" => digest,
      "source" => {"repository" => @policy.fetch("sourceRepository"), "commit" => @commit, "dirty" => false},
      "acceptance" => @policy.fetch("acceptance"), "qualifications" => qualifications, "artifacts" => entries,
    }
    @candidate_path = @candidate_root.join("candidate.json")
    @candidate_path.write(JSON.pretty_generate(@candidate) + "\n")
    @candidate_digest = Digest::SHA256.file(@candidate_path).hexdigest
    @verifier = {"repository" => @policy.fetch("verifierRepository"), "commit" => "f" * 40, "dirty" => false}
    automated = @policy.dig("acceptance", "automatedTargets").to_h do |target|
      run = {
        "schemaVersion" => 1, "kind" => "plugin-candidate-automated-run", "status" => "passed", "exitCode" => 0,
        "plugin" => "sfiora", "version" => "1.0.0", "candidateId" => @candidate.fetch("candidateId"),
        "artifactSetSha256" => digest, "candidateManifestSha256" => @candidate_digest, "target" => target,
        "command" => ["verification/sfiora/verify.sh", "--candidate", @candidate.fetch("candidateId"), target],
        "startedAt" => (Time.now.utc - 20).iso8601(6), "completedAt" => (Time.now.utc - 10).iso8601(6),
        "verifier" => {"repository" => @verifier.fetch("repository"), "commit" => @verifier.fetch("commit"),
                       "headAfter" => @verifier.fetch("commit"), "dirtyBefore" => false, "dirtyAfter" => false},
      }
      digest_run(run)
      [target, {"status" => "passed", "evidence" => run}]
    end
    manual = @policy.dig("acceptance", "manualTargets").to_h { |target| [target, {"status" => "passed"}] }
    @receipt = {
      "schemaVersion" => @policy.fetch("acceptanceReceiptSchemaVersion"), "kind" => "plugin-candidate-acceptance",
      "status" => "accepted", "plugin" => "sfiora", "version" => "1.0.0",
      "candidateId" => @candidate.fetch("candidateId"), "artifactSetSha256" => digest,
      "candidateManifestSha256" => @candidate_digest, "candidateSource" => @candidate.fetch("source"),
      "acceptanceRequirements" => @candidate.fetch("acceptance"),
      "checks" => {"automatedConsumers" => automated, "manualDeviceMatrix" => manual},
      "verifier" => @verifier, "recordedAt" => Time.now.utc.iso8601(6),
    }
    @receipt_path = @root.join("receipt.json")
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary
  end

  def git(*arguments)
    GitInputDigest.git(@product, *arguments)
  end

  def digest_run(run)
    original = run.reject { |key, _value| key == "runSha256" }
    run["runSha256"] = Digest::SHA256.hexdigest(JSON.pretty_generate(original) + "\n")
  end

  def run_gate(publisher: false, channel: "uniapp", source: nil)
    @receipt_path.write(JSON.pretty_generate(@receipt) + "\n")
    script = publisher ? "publish-accepted.rb" : "verify-publish-candidate.rb"
    command = [RbConfig.ruby, @product.join("scripts", script).to_s,
      "--candidate", @candidate_path.to_s, "--acceptance", @receipt_path.to_s]
    command.concat(["--channel", channel]) if publisher
    command.concat(["--source", source.to_s]) if source
    Open3.capture3({"SFIORA_CENTRAL_TOKEN" => nil}, *command)
  end

  def assert_rejected(pattern, publisher: false)
    _output, error, status = run_gate(publisher: publisher)
    refute status.success?, "Gate accepted invalid input"
    assert_match pattern, error
  end

  def snapshot_command(files, version: "1.0.0", state: "candidate", dirty: false, commit: @commit)
    command = [RbConfig.ruby, @product.join("scripts/snapshot-release-candidate.rb").to_s,
      "--plugin", "sfiora", "--policy", @product.join("release-policy.json").to_s,
      "--version", version, "--repository", @policy.fetch("sourceRepository"),
      "--commit", commit, "--dirty", dirty.to_s, "--root", @product.to_s, "--state", state]
    @candidate.fetch("qualifications").each { |key, value| command.concat(["--qualification", "#{key}=#{value}"]) }
    %w[automated manual].each do |kind|
      @policy.dig("acceptance", "#{kind}Targets").each { |target| command.concat(["--#{kind}-target", target]) }
    end
    files.each { |role, path| command.concat(["--artifact", "#{role}=#{path}"]) }
    command
  end

  def test_current_automated_results_and_simple_device_statuses_open_the_gate
    output, error, status = run_gate
    assert status.success?, error
    assert_match(/Verified checks and artifacts/, output)
    output, error, status = run_gate(publisher: true)
    assert status.success?, error
    %w[uniapp-legacy-package uniapp-uts-package].each do |role|
      assert_includes output, @candidate_root.join("artifacts", role).to_s
    end
    assert_includes output, "HBuilderX"
    assert_includes output, "发布到插件市场"
    assert_includes output, "Legacy compatibility/offline archive:"
  end

  def test_missing_or_unsuccessful_device_targets_block_publication
    checks = @receipt.dig("checks", "manualDeviceMatrix")
    target = checks.keys.first
    checks.delete(target)
    assert_rejected(/Manual acceptance targets differ/)
    %w[pending failed unknown].each do |status|
      checks[target] = {"status" => status}
      assert_rejected(/Manual device acceptance did not pass/)
    end
    checks[target] = {"status" => "passed"}
    checks["invented-device"] = {"status" => "passed"}
    assert_rejected(/Manual acceptance targets differ/)
  end

  def test_github_instructions_only_list_the_initial_eight_assets
    output, error, status = run_gate(publisher: true, channel: "github")
    assert status.success?, error
    roles = %w[native-ios-xcframework native-build-manifest react-native-package checksum-react-native-package
               uniapp-legacy-package checksum-uniapp-legacy-package uniapp-uts-package checksum-uniapp-uts-package]
    expected = @candidate.fetch("artifacts").select { |entry| roles.include?(entry.fetch("role")) }
      .map { |entry| @candidate_root.join(entry.fetch("file")).realpath.to_s }
    paths = output.lines.map(&:chomp).select { |line| line.start_with?(@candidate_root.realpath.to_s) }
    assert_equal expected.sort, paths.sort
    assert_includes output, "Instructions only"
    assert_includes output, "Mirror Android AAR"
  end

  def test_maven_instructions_need_no_token_and_only_name_the_signed_bundle
    output, error, status = run_gate(publisher: true, channel: "maven")
    assert status.success?, error
    paths = output.lines.map(&:chomp).select { |line| line.start_with?(@candidate_root.realpath.to_s) }
    assert_equal [@candidate_root.join("artifacts/sfiora-1.0.0-maven.zip").realpath.to_s], paths
    assert_includes output, "io.github.sandroxy:sfiora-ui:1.0.0"
    assert_includes output, "user-managed"
  end

  def test_npm_instructions_do_not_attempt_authentication_or_publication
    bin = @root.join("blocked-commands")
    bin.mkpath
    marker = @root.join("unexpected-publisher")
    %w[gh npm curl].each do |name|
      path = bin.join(name)
      path.write("#!/bin/sh\ntouch '#{marker}'\nexit 99\n")
      path.chmod(0755)
    end
    previous = ENV.fetch("PATH")
    ENV["PATH"] = "#{bin}:#{previous}"
    output, error, status = run_gate(publisher: true, channel: "npm")
    assert status.success?, error
    refute marker.exist?, "The manual publication guide invoked a publisher"
    assert_includes output, "publish-npm.yml"
    assert_includes output, "no npm settings page yet"
    assert_includes output, "--ignore-scripts"
  ensure
    ENV["PATH"] = previous if previous
  end

  def test_updated_publication_tools_can_verify_a_separate_clean_tag_checkout
    checkout = @root.join("release-source")
    git("worktree", "add", "--detach", checkout.to_s, "1.0.0")
    @product.join("publication-only.txt").write("updated workflow fixture")
    git("add", ".")
    git("commit", "-qm", "publication tools only")
    output, error, status = run_gate(publisher: true, channel: "github", source: checkout)
    assert status.success?, error
    assert_includes output, "Verified"
    assert_rejected(/Current source commit differs/)
    checkout.join("dirty.txt").write("unaccepted source")
    _output, error, status = run_gate(source: checkout)
    refute status.success?
    assert_match(/requires a clean source worktree/, error)
  end

  def test_public_android_mirror_verifies_both_core_and_ui_before_upload
    public_files = @root.join("public-assets")
    public_files.mkpath
    roles = %w[native-android-core-aar native-android-ui-aar native-build-manifest]
    @candidate.fetch("artifacts").select { |entry| roles.include?(entry.fetch("role")) }.each do |entry|
      filename = entry.fetch("role") == "native-build-manifest" ? "sfiora-native-1.0.0.json" : File.basename(entry.fetch("file"))
      FileUtils.cp(@candidate_root.join(entry.fetch("file")), public_files.join(filename))
    end
    command = ["python3", File.expand_path("../.github/scripts/verify-release-assets.py", __dir__),
      "--version", "1.0.0", "--source", @product.to_s, "--artifacts", public_files.to_s, "--channel", "android"]
    output, error, status = Open3.capture3(*command)
    assert status.success?, error
    assert_includes output, "Verified public android"
    ui = public_files.join("sfiora-ui-1.0.0.aar")
    ui.binwrite("x" * ui.size)
    _output, error, status = Open3.capture3(*command)
    refute status.success?
    assert_match(/Native artifact bytes differ: sfiora-ui/, error)
  end

  def test_publisher_runs_the_gate_before_reporting_upload_paths
    @receipt.dig("checks", "manualDeviceMatrix").values.first["status"] = "pending"
    assert_rejected(/Manual device acceptance did not pass/, publisher: true)
  end

  def test_incomplete_or_failed_automated_checks_block_publication
    checks = @receipt.dig("checks", "automatedConsumers")
    target = checks.keys.first
    original = checks.delete(target)
    assert_rejected(/Automated acceptance targets differ/)
    checks[target] = {"status" => "pending"}
    assert_rejected(/Automated consumer acceptance did not pass/)
    checks[target] = original.merge("status" => "failed")
    assert_rejected(/Automated consumer acceptance did not pass/)
  end

  def test_automated_evidence_must_match_the_candidate_and_verifier
    evidence = @receipt.dig("checks", "automatedConsumers").values.first.fetch("evidence")
    evidence["candidateId"] = "another-candidate"
    digest_run(evidence)
    assert_rejected(/Automated evidence candidate differs/)
    evidence["candidateId"] = @candidate.fetch("candidateId")
    evidence.fetch("verifier")["commit"] = "e" * 40
    evidence.fetch("verifier")["headAfter"] = "e" * 40
    digest_run(evidence)
    assert_rejected(/Automated evidence verifier differs/)
  end

  def test_receipt_identity_and_execution_times_are_checked
    @receipt["candidateManifestSha256"] = "a" * 64
    assert_rejected(/Acceptance receipt candidateManifestSha256 differs/)
    @receipt["candidateManifestSha256"] = @candidate_digest
    @receipt["recordedAt"] = (Time.now.utc + 3600).iso8601(6)
    assert_rejected(/Acceptance timestamp is in the future/)
    @receipt["recordedAt"] = Time.now.utc.iso8601(6)
    evidence = @receipt.dig("checks", "automatedConsumers").values.first.fetch("evidence")
    evidence["completedAt"] = (Time.now.utc + 3600).iso8601(6)
    digest_run(evidence)
    assert_rejected(/Automated evidence time range differs/)
  end

  def test_modified_artifacts_block_publication
    @candidate_root.join(@candidate.fetch("artifacts").first.fetch("file")).write("changed bytes")
    assert_rejected(/artifact byte count differs|artifact checksum differs/)
  end

  def test_dirty_or_different_source_blocks_publication
    @product.join("source-change.txt").write("changed release source")
    assert_rejected(/requires a clean source worktree/)
    git("add", ".")
    git("commit", "-qm", "changed fixture")
    assert_rejected(/Current source commit differs/)
  end

  def test_canonical_tag_must_be_annotated_and_point_to_the_candidate
    git("tag", "-d", "1.0.0")
    assert_rejected(/Canonical annotated tag .* is missing/)
    git("tag", "1.0.0")
    assert_rejected(/Canonical annotated tag .* is missing/)
    git("tag", "-d", "1.0.0")
    other_commit = git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "other fixture").strip
    git("tag", "-a", "1.0.0", other_commit, "-m", "wrong fixture target")
    assert_rejected(/does not point to the accepted source commit/)
  end

  def test_recording_keeps_one_artifact_set_and_retires_only_known_old_outputs
    files = @candidate.fetch("artifacts").to_h do |entry|
      path = @candidate_root.join("packages", "#{entry.fetch('role')}-2.0.0.bin")
      path.parent.mkpath
      path.write(entry.fetch("role"))
      [entry.fetch("role"), path]
    end
    selected = files.values.first
    older = selected.sub("2.0.0", "0.9.0")
    stable = selected.sub("2.0.0", "1.0.0")
    unknown = @candidate_root.join("packages/unrelated-0.9.0.txt")
    historical = @candidate_root.join("candidates/0.9.0/old-candidate/artifacts", older.basename)
    historical.parent.mkpath
    [older, stable, unknown, historical].each { |path| path.write("retention fixture") }
    symlink = selected.sub("2.0.0", "0.8.0")
    File.symlink(unknown, symlink)
    directory = selected.sub("2.0.0", "0.7.0")
    directory.mkpath
    original_stats = files.values.map { |path| [path.stat.ino, path.stat.mtime] }
    command = snapshot_command(files, version: "2.0.0")
    output, error, status = Open3.capture3(*command)
    assert status.success?, error
    assert_equal @candidate_path.realpath.to_s, output.lines.first.strip
    manifest = JSON.parse(@candidate_path.read)
    assert_equal files.values.map(&:to_s).sort,
      manifest.fetch("artifacts").map { |entry| @candidate_root.join(entry.fetch("file")).to_s }.sort
    assert_equal original_stats, files.values.map { |path| [path.stat.ino, path.stat.mtime] }
    refute older.exist?
    [stable, unknown, historical].each { |path| assert path.file? }
    assert symlink.symlink?
    assert directory.directory?
    refute @candidate_root.join("candidates/2.0.0").exist?
    manifest_stat = @candidate_path.stat
    _output, error, status = Open3.capture3(*command)
    assert status.success?, error
    assert_equal [manifest_stat.ino, manifest_stat.mtime], [@candidate_path.stat.ino, @candidate_path.stat.mtime]
    selected.write("changed artifact")
    _output, error, status = Open3.capture3(*command)
    assert status.success?, error
    changed = JSON.parse(@candidate_path.read)
    refute_equal manifest.fetch("candidateId"), changed.fetch("candidateId")
    @product.join("source-change.txt").write("new source commit")
    git("add", ".")
    git("commit", "-qm", "new source")
    _output, error, status = Open3.capture3(*snapshot_command(files, version: "2.0.0", commit: git("rev-parse", "HEAD").strip))
    assert status.success?, error
    refute_equal changed.fetch("candidateId"), JSON.parse(@candidate_path.read).fetch("candidateId")
    assert_equal [@candidate_path], @candidate_root.glob("*.json")
    original_manifest = @candidate_path.binread
    older.write("must survive a failed candidate")
    selected.unlink
    _output, error, status = Open3.capture3(*command)
    refute status.success?
    assert_match(/not a regular file/, error)
    assert older.file?
    assert_equal original_manifest, @candidate_path.binread
  end

  def test_unsafe_recording_paths_preserve_the_previous_manifest
    files = @candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), @candidate_root.join(entry.fetch("file"))] }
    role, path = files.first
    outside = @root.join("outside.bin")
    outside.write("outside fixture")
    symlink = @candidate_root.join("linked-artifact")
    File.symlink(path, symlink)
    linked_directory = @candidate_root.join("linked-directory")
    File.symlink(path.parent, linked_directory)
    original_manifest = @candidate_path.binread
    [outside, symlink, linked_directory.join(path.basename), @candidate_path].each do |invalid_path|
      _output, error, status = Open3.capture3(*snapshot_command(files.merge(role => invalid_path)))
      refute status.success?
      assert_match(/escapes|symbolic link|cannot be an artifact/, error)
      assert_equal original_manifest, @candidate_path.binread
    end
  end

  def test_rehearsal_uses_the_current_manifest_but_cannot_be_published
    files = @candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), @candidate_root.join(entry.fetch("file"))] }
    _output, error, status = Open3.capture3(*snapshot_command(files, state: "rehearsal", dirty: true))
    assert status.success?, error
    manifest = JSON.parse(@candidate_path.read)
    assert_equal "rehearsal", manifest.fetch("state")
    assert_equal false, manifest.fetch("acceptanceEligible")
    refute @candidate_root.join("rehearsals").exist?
    assert_rejected(/Candidate is not acceptance eligible/, publisher: true)
  end

  def test_rerecording_changed_bytes_invalidates_previous_acceptance
    files = @candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), @candidate_root.join(entry.fetch("file"))] }
    files.fetch("react-native-package").write("replacement package")
    _output, error, status = Open3.capture3(*snapshot_command(files))
    assert status.success?, error
    assert_rejected(/Acceptance receipt candidateId differs/, publisher: true)
  end
end
