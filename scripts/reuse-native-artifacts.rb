#!/usr/bin/env ruby

require "fileutils"
require "optparse"
require "tempfile"
require_relative "native-release-manifest"
require_relative "verify-maven-signatures"

options = { groups: [], plan: false, replace: false }
OptionParser.new do |parser|
  parser.banner = "Usage: reuse-native-artifacts.rb --candidate FILE [--group NAME ... --proof FILE | --plan] [--signature-fingerprint FINGERPRINT] [--replace]"
  parser.on("--candidate FILE") { |value| options[:candidate] = value }
  parser.on("--group NAME") { |value| options[:groups] << value }
  parser.on("--proof FILE") { |value| options[:proof] = value }
  parser.on("--plan", "Compare committed inputs without changing outputs") { options[:plan] = true }
  parser.on("--signature-fingerprint FINGERPRINT", "Existing public key for Android signature verification") { |value| options[:signer] = value }
  parser.on("--replace", "Replace existing mutable outputs") { options[:replace] = true }
  parser.on("-h", "--help") { puts parser; exit }
end.parse!

begin
  raise NativeArtifactReuse::Error, "A candidate is required; unexpected positional arguments are forbidden" unless
    options[:candidate] && ARGV.empty?
  root = Pathname.new(__dir__).parent.realpath
  policy = ReleasePolicy.load(root.join("release-policy.json"))
  definitions = NativeArtifactReuse.groups(policy: policy)
  selected = options.fetch(:groups)
  raise NativeArtifactReuse::Error, "Unknown or duplicate reuse groups" unless
    selected.uniq == selected && (selected - definitions.keys).empty?
  raise NativeArtifactReuse::Error, "Choose --plan or explicit --group and --proof options" unless
    (options[:plan] && !options[:proof]) || (!options[:plan] && !selected.empty? && options[:proof])
  selected = definitions.keys if selected.empty?
  head = if options[:plan]
           GitInputDigest.git(root, "rev-parse", "HEAD").strip
         else
           GitInputDigest.clean_head!(root)
         end
  version = JSON.parse(root.join("plugin.json").read).fetch("version")
  candidate, candidate_root = NativeArtifactReuse.load_candidate!(options.fetch(:candidate), policy: policy)
  raise NativeArtifactReuse::Error, "Candidate version differs from the release target" unless
    candidate.fetch("version") == version
  source_commit = candidate.dig("source", "commit")
  GitInputDigest.ancestor!(root, source_commit, head)
  entries = candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
  manifest = JSON.parse(candidate_root.join(entries.fetch("native-build-manifest").fetch("file")).read)
  NativeReleaseManifest.validate!(manifest, version: version, policy: policy)
  NativeReleaseManifest.verify_candidate!(manifest, candidate: candidate)
  NativeReleaseManifest.verify_reuse!(manifest, root: root)
  raise NativeArtifactReuse::Error, "Source native manifest does not belong to the candidate" unless
    manifest.fetch("commit") == source_commit && manifest.fetch("dirty") == false &&
      manifest.fetch("androidMavenSigned") == true
  proof = {
    "sourceCandidate" => candidate,
    "sourceCandidateSha256" => Digest::SHA256.hexdigest(NativeArtifactReuse.canonical_json(candidate)),
    "platformInputs" => {},
  }
  selected.each do |name|
    scopes = definitions.fetch(name).fetch("inputs")
    previous = GitInputDigest.digest(root, source_commit, scopes)
    current = GitInputDigest.digest(root, head, scopes)
    if options[:plan]
      puts "#{name}: #{previous == current ? 'reuse eligible by committed inputs' : 'rebuild required: tracked inputs changed'}"
    else
      raise NativeArtifactReuse::Error, "#{name} inputs changed; rebuild instead of reusing" unless previous == current
      proof.fetch("platformInputs")[name] = current
    end
  end
  if options[:plan]
    unless GitInputDigest.git(root, "status", "--porcelain", "--untracked-files=all").empty?
      puts "Worktree is dirty: this plan compares committed inputs only and does not authorize preparation."
    end
    puts "Read-only comparison at #{head}; no artifact or acceptance evidence was changed."
    exit 0
  end
  NativeArtifactReuse.validate!(proof, manifest: manifest, policy: policy)
  NativeArtifactReuse.verify_inputs!(proof, root: root, commit: head, definitions: definitions)
  _output, error, status = Open3.capture3("bash", "-c", 'source "$1"; sfiora_assert_version_unpublished',
    "sfiora-reuse", root.join("scripts/release-common.sh").to_s)
  raise NativeArtifactReuse::Error, error.strip unless status.success?

  if selected.include?("android")
    MavenSignatures.verify!(
      repository: candidate_root.join(entries.fetch("native-android-maven-repository").fetch("file")),
      aars: {"sfiora" => candidate_root.join(entries.fetch("native-android-core-aar").fetch("file")),
             "sfiora-ui" => candidate_root.join(entries.fetch("native-android-ui-aar").fetch("file"))},
      version: version, signer: options[:signer]
    )
  elsif options[:signer]
    raise NativeArtifactReuse::Error, "A signing fingerprint applies only to Android reuse"
  end
  if selected.include?("ios")
    NativeReleaseManifest.verify_ios!(manifest, root: root,
      archive: candidate_root.join(entries.fetch("native-ios-xcframework").fetch("file")))
  end
  proof_path = Pathname.new(options.fetch(:proof))
  raise NativeArtifactReuse::Error, "Proof path must be absolute and must not exist" unless
    proof_path.absolute? && !proof_path.exist? && !proof_path.symlink? && proof_path.parent.directory?
  proof_path = proof_path.parent.realpath.join(proof_path.basename)
  raise NativeArtifactReuse::Error, "Reuse proof must not be written inside the source snapshot" if
    proof_path.to_s.start_with?(candidate_root.to_s + "/")
  copies = selected.flat_map do |name|
    group = definitions.fetch(name)
    group.fetch("roles").flat_map do |role|
      [role, "checksum-#{role}"].map do |copy_role|
        entry = entries.fetch(copy_role)
        destination = root.join("dist", group.fetch("directory"), File.basename(entry.fetch("file")))
        [candidate_root.join(entry.fetch("file")), destination, entry]
      end
    end
  end
  destinations = copies.map { |_source, destination, _entry| destination }
  raise NativeArtifactReuse::Error, "Reuse output paths collide" unless
    destinations.uniq == destinations && !destinations.include?(proof_path)
  copies.each do |source, destination, entry|
    raise NativeArtifactReuse::Error, "Reuse must not overwrite its source snapshot" if
      source != destination && destination.to_s.start_with?(candidate_root.to_s + "/")
    cursor = root
    destination.relative_path_from(root).each_filename do |part|
      cursor = cursor.join(part)
      raise NativeArtifactReuse::Error, "Reuse destination uses a symbolic link: #{cursor}" if cursor.symlink?
    end
    raise NativeArtifactReuse::Error, "Reuse destination is not a regular file: #{destination}" if
      destination.exist? && !destination.file?
    if destination.file? && !options[:replace]
      raise NativeArtifactReuse::Error, "Output already exists with different bytes; use --replace: #{destination}" unless
        destination.size == entry.fetch("bytes") && Digest::SHA256.file(destination).hexdigest == entry.fetch("sha256")
    end
  end
  GitInputDigest.clean_head!(root, head)
  copies.each do |source, destination, entry|
    if source == destination
      raise NativeArtifactReuse::Error, "Source changed while reusing: #{source}" unless
        source.file? && source.size == entry.fetch("bytes") &&
          Digest::SHA256.file(source).hexdigest == entry.fetch("sha256")
      next
    end
    FileUtils.mkdir_p(destination.parent)
    Tempfile.create([".reuse-", ".tmp"], destination.parent.to_s) do |temporary|
      temporary.binmode
      temporary.write(source.binread)
      temporary.flush
      raise NativeArtifactReuse::Error, "Source changed while copying: #{source}" unless
        temporary.size == entry.fetch("bytes") && Digest::SHA256.file(temporary.path).hexdigest == entry.fetch("sha256")
      File.chmod(0o644, temporary.path)
      File.rename(temporary.path, destination)
    end
  end
  GitInputDigest.clean_head!(root, head)
  File.open(proof_path, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |file|
    file.write(NativeArtifactReuse.canonical_json(proof))
  end
  puts "Reused exact candidate artifacts: #{selected.join(', ')}. No manual acceptance was recorded."
rescue NativeArtifactReuse::Error, NativeReleaseManifest::Error, GitInputDigest::Error,
       ReleasePolicy::Error, MavenSignatures::Error, KeyError, JSON::ParserError, SystemCallError => error
  abort(error.message)
end
