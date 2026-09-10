#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "native-release-manifest"

class NativeArtifactReuseTest < Minitest::Test
  def setup
    @repository = Pathname.new(__dir__).parent
    @policy = ReleasePolicy.load(@repository.join("release-policy.json"))
    @definitions = NativeArtifactReuse.groups(policy: @policy)
    @temporary = Dir.mktmpdir("native-artifact-reuse-test-")
    @root = Pathname.new(@temporary)
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    @definitions.values.flat_map { |group| group.fetch("inputs") }.uniq.each do |scope|
      path = @root.join(scope)
      path = path.join("input.txt") if @repository.join(scope).directory?
      FileUtils.mkdir_p(path.parent)
      path.write("tracked input\n")
    end
    @before = commit
    @root.join("unrelated.txt").write("unrelated\n")
    @after = commit
    @snapshot = @root.join("snapshot")
    qualifications = @policy.fetch("qualifications").to_h { |key| [key, true] }
    @entries = ReleasePolicy.expected_artifact_roles(@policy, qualifications).sort.map do |role|
      primary = role.delete_prefix("checksum-")
      filename = NativeReleaseManifest.paths("1.0.0")[primary]
      filename = filename ? File.basename(filename) + (role.start_with?("checksum-") ? ".sha256" : "") : role
      file = @snapshot.join("artifacts", filename)
      FileUtils.mkdir_p(file.parent)
      file.write(role + "\n")
      {"role" => role, "file" => "artifacts/#{filename}", "bytes" => file.size,
       "sha256" => Digest::SHA256.file(file).hexdigest}
    end
    payload = @entries.map { |entry| %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n" }.join
    digest = Digest::SHA256.hexdigest(payload)
    @candidate = {
      "schemaVersion" => @policy.fetch("candidateSchemaVersion"), "kind" => "plugin-release-candidate",
      "state" => "candidate", "acceptanceEligible" => true, "plugin" => "sfiora", "version" => "1.0.0",
      "candidateId" => "sfiora-1.0.0-#{@before[0, 12]}-#{digest[0, 12]}", "artifactSetSha256" => digest,
      "source" => {"repository" => @policy.fetch("sourceRepository"), "commit" => @before, "dirty" => false},
      "acceptance" => @policy.fetch("acceptance"), "qualifications" => qualifications, "artifacts" => @entries
    }
    @candidate_path = @snapshot.join("candidate.json")
    @candidate_path.write(NativeArtifactReuse.canonical_json(@candidate))
    native_roles = @definitions.values.flat_map { |group| group.fetch("roles") }
    @manifest = {
      "schemaVersion" => 2, "plugin" => "sfiora", "version" => "1.0.0", "commit" => @after,
      "dirty" => false, "androidMavenSigned" => true,
      "iosBinarySourceCommit" => @before, "iosBinaryPromoted" => true,
      "artifacts" => @entries.select { |entry| native_roles.include?(entry.fetch("role")) }.map do |entry|
        {"file" => NativeReleaseManifest.paths("1.0.0").fetch(entry.fetch("role")), "bytes" => entry.fetch("bytes"), "sha256" => entry.fetch("sha256")}
      end
    }
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary
  end

  def git(*arguments)
    GitInputDigest.git(@root, *arguments).strip
  end

  def commit
    git("add", ".")
    git("commit", "-qm", "fixture")
    git("rev-parse", "HEAD")
  end

  def proof(names = @definitions.keys)
    {
      "sourceCandidate" => @candidate,
      "sourceCandidateSha256" => Digest::SHA256.hexdigest(NativeArtifactReuse.canonical_json(@candidate)),
      "platformInputs" => names.to_h do |name|
        [name, GitInputDigest.digest(@root, @before, @definitions.fetch(name).fetch("inputs"))]
      end
    }
  end

  def test_each_configured_group_can_be_reused_independently
    @definitions.each_key do |name|
      record = proof([name])
      assert_equal record, NativeArtifactReuse.validate!(record, manifest: @manifest)
      NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after)
      @manifest["artifactReuse"] = record
      assert_equal @manifest, NativeReleaseManifest.validate!(@manifest, version: "1.0.0")
    end
  end

  def test_full_snapshot_is_verified_without_mutation
    original = @candidate_path.binread
    loaded, directory = NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy)
    assert_equal @candidate, loaded
    assert_equal @snapshot.realpath, directory
    assert_equal original, @candidate_path.binread
  end

  def test_unselected_artifact_tampering_also_rejects_the_source_snapshot
    @snapshot.join(@entries.last.fetch("file")).write("modified")
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
  end

  def test_changed_acceptance_contract_preserves_unchanged_native_artifacts
    @candidate["acceptance"] = @policy.fetch("acceptance").merge("manualScenarios" => ["read-and-write"])
    @candidate_path.write(NativeArtifactReuse.canonical_json(@candidate))
    assert_raises(ReleasePolicy::Error) { ReleasePolicy.validate_candidate!(@candidate, @policy) }
    loaded, = NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy)
    assert_equal @candidate, loaded
    record = proof
    NativeArtifactReuse.validate!(record, manifest: @manifest, policy: @policy)
    NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after)
    @manifest["artifactReuse"] = record
    assert_equal @manifest, NativeReleaseManifest.validate!(@manifest, version: "1.0.0")
  end

  def test_symlink_and_missing_artifact_reject_the_snapshot
    path = @snapshot.join(@entries.first.fetch("file"))
    path.delete
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
    File.symlink(@snapshot.join(@entries.last.fetch("file")), path)
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
  end

  def test_changed_native_input_invalidates_only_its_group
    record = proof
    @root.join("native/android/input.txt").write("new implementation")
    @after = commit
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after) }
    unaffected = proof(@definitions.keys - ["android"])
    NativeArtifactReuse.verify_inputs!(unaffected, root: @root, commit: @after)
  end

  def test_ios_project_scheme_and_workspace_are_in_scope
    %w[Sfiora.xcodeproj/xcshareddata/xcschemes/Sfiora.xcscheme Sfiora.xcodeproj/project.xcworkspace/contents.xcworkspacedata].each do |relative|
      path = @root.join("native/ios", relative)
      FileUtils.mkdir_p(path.parent)
      path.write("changed build input")
      @after = commit
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof(["ios"]), root: @root, commit: @after) }
    end
  end

  def test_packaging_and_legal_input_changes_reject_reuse
    ["scripts/package-native-android.sh", "LICENSE"].each do |relative|
      @root.join(relative).write("changed")
      @after = commit
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof(["android"]), root: @root, commit: @after) }
    end
  end

  def test_unknown_empty_or_forged_proof_rejected
    [
      ->(value) { value["platformInputs"] = {} },
      ->(value) { value["platformInputs"]["unknown"] = "a" * 64 },
      ->(value) { value["platformInputs"]["android"] = "invalid" },
      ->(value) { value["sourceCandidateSha256"] = "a" * 64 },
      ->(value) { value["extra"] = true },
    ].each do |mutation|
      record = JSON.parse(NativeArtifactReuse.canonical_json(proof))
      mutation.call(record)
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(record, manifest: @manifest) }
    end
  end

  def test_changed_artifact_or_unsigned_destination_rejects_reuse
    @manifest["androidMavenSigned"] = false
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(proof, manifest: @manifest) }
    @manifest["androidMavenSigned"] = true
    @manifest.fetch("artifacts").first["sha256"] = "f" * 64
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(proof, manifest: @manifest) }
  end

  def test_wrong_commit_or_missing_history_rejects_reuse
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof, root: @root, commit: "f" * 40) }
    record = proof
    record["platformInputs"]["android"] = "f" * 64
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after) }
  end

  def test_policy_cannot_omit_duplicate_or_invent_roles
    configuration = JSON.parse(@repository.join("native-reuse-policy.json").read)
    [
      ->(value) { value["groups"].delete("ios") },
      ->(value) { value["groups"]["ios"]["roles"] = ["unknown"] },
      ->(value) { value["groups"]["ios"]["directory"] = "../../escape" },
      ->(value) { value["groups"]["ios"]["inputs"] = [] },
    ].each do |mutation|
      changed = JSON.parse(JSON.generate(configuration))
      mutation.call(changed)
      path = @root.join("policy.json")
      path.write(JSON.pretty_generate(changed))
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.groups(policy: @policy, path: path) }
    end
  end

  def preparation_fixture(in_place: false)
    names = %w[prepare-native-release.sh reuse-native-artifacts.rb native-release-manifest.rb
      native-artifact-reuse.rb native-input-digest.rb git-input-digest.rb release-policy.rb release-common.sh]
    names.each { |name| FileUtils.cp(@repository.join("scripts", name), @root.join("scripts", name)) }
    %w[release-policy.json native-reuse-policy.json plugin.json].each do |name|
      FileUtils.cp(@repository.join(name), @root.join(name))
    end
    # The fixture owns its version independently of the next product release.
    manifest_path = @root.join("plugin.json")
    manifest = JSON.parse(manifest_path.read).merge("version" => @candidate.fetch("version"))
    manifest_path.write(JSON.pretty_generate(manifest) + "\n")
    @root.join(".gitignore").write("/dist/\n/snapshot/\n")
    @root.join("scripts/assert-release-version-available.rb").write("exit 0\n")
    scripts = {
      "verify-release-metadata.sh" => "exit 0\n",
      "package-native.sh" => "echo Unexpected-full-rebuild >&2; exit 91\n",
      "verify-native-android.sh" => "printf 'verify-android\\n' >> \"$SFIORA_TEST_EVENTS\"\n",
      "verify-native-ios.sh" => "printf 'verify-ios\\n' >> \"$SFIORA_TEST_EVENTS\"\n",
      "verify-ios-xcframework-provenance.sh" => "printf '%s %s\\n' \"$SFIORA_TEST_IOS_SOURCE\" \"#{'a' * 64}\"\n",
    }
    @definitions.each_key { |group| scripts["package-native-#{group}.sh"] = "echo Unexpected-selected-rebuild >&2; exit 92\n" }
    scripts.each do |name, content|
      path = @root.join("scripts", name)
      path.write("#!/bin/sh\nset -eu\n" + content)
      File.chmod(0o755, path)
    end
    # Signature bytes and signer checks are exercised separately with real ZIPs.
    @root.join("scripts/verify-maven-signatures.rb").write(<<~RUBY)
      module MavenSignatures
        class Error < StandardError; end
        def self.verify!(**arguments)
          raise Error, "Wrong public signer" unless arguments.fetch(:signer) == "#{'A' * 40}"
          File.open(ENV.fetch("SFIORA_TEST_EVENTS"), "a") { |file| file.puts("verify-existing-signatures") }
        end
      end
    RUBY
    @before = commit
    @root.join("unrelated.txt").write("release metadata adjustment\n")
    @after = commit
    @manifest["commit"] = @before
    @manifest["iosBinarySourceCommit"] = @before
    refresh_snapshot
    @root.join("dist").mkpath
    git("init", "--bare", "--quiet", @root.join("dist/origin.git").to_s)
    git("remote", "add", "origin", @root.join("dist/origin.git").to_s)
    @environment = {
      "TMPDIR" => @root.join("dist").to_s,
      "SFIORA_SIGNING_KEY" => nil, "SFIORA_SIGNING_PASSWORD" => nil,
      "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP" => nil, "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256" => nil,
      "SFIORA_IOS_ACCEPTED_SOURCE_COMMIT" => nil,
      "SFIORA_TEST_IOS_SOURCE" => @before, "SFIORA_TEST_EVENTS" => @root.join("dist/events").to_s
    }
    if in_place
      paths = NativeReleaseManifest.paths("1.0.0")
      paths["native-build-manifest"] = "dist/native-release/sfiora-native-1.0.0.json"
      paths["native-build-checksums"] = "dist/native-release/sfiora-native-1.0.0-SHA256SUMS"
      @entries.each do |entry|
        role = entry.fetch("role")
        relative = paths.fetch(role.delete_prefix("checksum-"), "dist/packages/#{role}").delete_prefix("dist/")
        relative += ".sha256" if role.start_with?("checksum-")
        destination = @root.join("dist", relative)
        destination.parent.mkpath
        FileUtils.mv(@snapshot.join(entry.fetch("file")), destination)
        entry["file"] = relative
      end
      # Reuse proofs must be outside the source candidate directory.
      @environment["TMPDIR"] = @snapshot.to_s
      @snapshot = @root.join("dist")
      @candidate_path = @snapshot.join("candidate.json")
      refresh_snapshot
    end
  end

  def refresh_snapshot
    @candidate.fetch("source")["commit"] = @before
    native = @entries.to_h { |entry| [entry.fetch("role"), entry] }
    @manifest["artifacts"] = NativeReleaseManifest.paths("1.0.0").map do |role, relative|
      entry = native.fetch(role)
      {"file" => relative, "bytes" => entry.fetch("bytes"), "sha256" => entry.fetch("sha256")}
    end
    entry = native.fetch("native-build-manifest")
    @snapshot.join(entry.fetch("file")).write(JSON.pretty_generate(@manifest) + "\n")
    @entries.each do |item|
      path = @snapshot.join(item.fetch("file"))
      item["bytes"] = path.size
      item["sha256"] = Digest::SHA256.file(path).hexdigest
    end
    payload = @entries.sort_by { |item| item.fetch("role") }.map do |item|
      %w[role file bytes sha256].map { |key| item.fetch(key) }.join("\t") + "\n"
    end.join
    @candidate["artifactSetSha256"] = Digest::SHA256.hexdigest(payload)
    @candidate["candidateId"] = "sfiora-1.0.0-#{@before[0, 12]}-#{@candidate.fetch('artifactSetSha256')[0, 12]}"
    @candidate_path.write(JSON.pretty_generate(@candidate) + "\n")
  end

  def prepare(*groups, extra: [], environment: {})
    arguments = ["bash", @root.join("scripts/prepare-native-release.sh").to_s,
      "--reuse-candidate", @candidate_path.to_s]
    groups.each { |group| arguments.concat(["--reuse", group]) }
    arguments.concat(["--signature-fingerprint", "A" * 40]) if groups.include?("android")
    Open3.capture3(@environment.merge(environment), *arguments, *extra, chdir: @root.to_s)
  end

  def test_preparation_reuses_both_platforms_without_building_or_signing
    preparation_fixture
    original = @candidate_path.binread
    output, error, status = prepare("android", "ios")
    assert status.success?, output + error
    assert_equal %w[verify-existing-signatures verify-android verify-ios], @root.join("dist/events").read.lines.map(&:chomp)
    released = JSON.parse(@root.join("dist/native-release/sfiora-native-1.0.0.json").read)
    assert_equal @after, released.fetch("commit")
    assert_equal @before, released.fetch("iosBinarySourceCommit")
    assert_equal @candidate, released.dig("artifactReuse", "sourceCandidate")
    assert_equal %w[android ios], released.dig("artifactReuse", "platformInputs").keys.sort
    assert_equal original, @candidate_path.binread
    NativeReleaseManifest.verify_files!(released, root: @root)
    NativeReleaseManifest.verify_reuse!(released, root: @root)
    assert_equal @after, GitInputDigest.clean_head!(@root)
  end

  def test_preparation_reuses_current_artifacts_in_place
    preparation_fixture(in_place: true)
    roles = @definitions.values.flat_map { |group| group.fetch("roles") }
    native_files = @entries.select { |entry| roles.include?(entry.fetch("role").delete_prefix("checksum-")) }
      .map { |entry| @snapshot.join(entry.fetch("file")) }
    original_stats = native_files.map { |path| [path.stat.ino, path.stat.mtime, Digest::SHA256.file(path).hexdigest] }
    original_candidate = @candidate_path.binread
    output, error, status = prepare("android", "ios")
    assert status.success?, output + error
    assert_equal original_stats, native_files.map { |path| [path.stat.ino, path.stat.mtime, Digest::SHA256.file(path).hexdigest] }
    assert_equal %w[verify-existing-signatures verify-android verify-ios], @root.join("dist/events").read.lines.map(&:chomp)
    released = JSON.parse(@root.join("dist/native-release/sfiora-native-1.0.0.json").read)
    assert_equal @after, released.fetch("commit")
    assert_equal @before, released.fetch("iosBinarySourceCommit")
    assert_equal @candidate, released.dig("artifactReuse", "sourceCandidate")
    assert_equal original_candidate, @candidate_path.binread
    NativeReleaseManifest.verify_files!(released, root: @root)
    NativeReleaseManifest.verify_reuse!(released, root: @root)
    assert_empty @root.glob("snapshot/sfiora-native-reuse.*")
    assert_equal @after, GitInputDigest.clean_head!(@root)
  end

  def test_current_candidate_does_not_allow_copying_over_another_source_file
    preparation_fixture(in_place: true)
    entry = @entries.find { |item| item.fetch("role") == "native-android-core-aar" }
    destination = @snapshot.join(entry.fetch("file"))
    original = destination.binread
    source = @snapshot.join("packages", destination.basename)
    FileUtils.cp(destination, source)
    entry["file"] = source.relative_path_from(@snapshot).to_s
    refresh_snapshot
    _output, error, status = prepare("android", "ios", extra: ["--replace"])
    refute status.success?
    assert_match(/must not overwrite its source snapshot/, error)
    assert_equal original, destination.binread
  end

  def test_ios_reuse_does_not_waive_android_signing_credentials
    preparation_fixture
    _output, error, status = prepare("ios")
    refute status.success?
    assert_match(/requires SFIORA_SIGNING_KEY/, error)
    refute @root.join("dist/events").exist?
  end

  def test_changed_android_is_built_while_ios_bytes_are_reused
    preparation_fixture
    @root.join("native/android/input.txt").write("changed Android implementation\n")
    @root.join("scripts/package-native-android.sh").write(<<~SHELL)
      #!/bin/sh
      set -eu
      printf 'build-android\\n' >> "$SFIORA_TEST_EVENTS"
      mkdir -p dist/native-android
      printf 'new core' > dist/native-android/sfiora-1.0.0.aar
      printf 'new ui' > dist/native-android/sfiora-ui-1.0.0.aar
      printf 'new signed repository' > dist/native-android/sfiora-1.0.0-maven.zip
    SHELL
    @after = commit
    output, error, status = prepare("ios", environment: {"SFIORA_SIGNING_KEY" => "fixture-only"})
    assert status.success?, output + error
    assert_equal %w[build-android verify-android verify-ios], @root.join("dist/events").read.lines.map(&:chomp)
    released = JSON.parse(@root.join("dist/native-release/sfiora-native-1.0.0.json").read)
    assert_equal ["ios"], released.dig("artifactReuse", "platformInputs").keys
    assert_equal @after, released.fetch("commit")
    assert_equal @before, released.fetch("iosBinarySourceCommit")
  end

  def test_invalid_reuse_selection_and_competing_ios_source_fail_before_builds
    preparation_fixture
    [
      ["android", "android"], ["unknown"],
    ].each do |groups|
      _output, _error, status = prepare(*groups)
      refute status.success?
    end
    %w[--allow-dirty --allow-unsigned].each do |flag|
      _output, _error, status = prepare("android", "ios", extra: [flag])
      refute status.success?
    end
    _output, error, status = prepare("android", "ios", environment: {
      "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP" => "/fixture/archive", "SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256" => "a" * 64,
      "SFIORA_IOS_ACCEPTED_SOURCE_COMMIT" => @before
    })
    refute status.success?
    assert_match(/cannot be combined/, error)
    refute @root.join("dist/events").exist?
  end

  def test_plan_does_not_copy_artifacts_or_claim_worktree_eligibility
    preparation_fixture
    @root.join("native/android/input.txt").write("uncommitted change")
    output, error, status = Open3.capture3(@environment, RbConfig.ruby,
      @root.join("scripts/reuse-native-artifacts.rb").to_s, "--candidate", @candidate_path.to_s, "--plan", chdir: @root.to_s)
    assert status.success?, error
    assert_match(/Worktree is dirty/, output)
    refute @root.join("dist/native-ios").exist?
    refute @root.join("dist/events").exist?
  end

  def test_different_mutable_outputs_require_explicit_replacement
    preparation_fixture
    @root.join("dist/native-android").mkpath
    existing = @root.join("dist/native-android/sfiora-1.0.0.aar")
    existing.write("keep existing bytes")
    _output, error, status = prepare("android", "ios")
    refute status.success?
    assert_match(/use --replace/, error)
    assert_equal "keep existing bytes", existing.read
    output, error, status = prepare("android", "ios", extra: ["--replace"])
    assert status.success?, output + error
    assert_equal @snapshot.join("artifacts/sfiora-1.0.0.aar").binread, existing.binread
  end

  def test_build_failure_preserves_exit_status_and_cleans_reuse_workspace
    preparation_fixture
    builder = @root.join("scripts/package-native-android.sh")
    builder.write("#!/bin/sh\necho fixture-build-failed >&2\nexit 77\n")
    @after = commit
    _output, error, status = prepare("ios", environment: {"SFIORA_SIGNING_KEY" => "fixture-only"})
    assert_equal 77, status.exitstatus
    assert_match(/fixture-build-failed/, error)
    assert_empty @root.glob("dist/sfiora-native-reuse.*")
    refute @root.join("dist/native-release").exist?
  end
end
