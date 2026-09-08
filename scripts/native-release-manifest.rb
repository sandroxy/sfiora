require_relative "native-artifact-reuse"
require_relative "native-input-digest"

module NativeReleaseManifest
  class Error < StandardError; end

  ARTIFACTS = {
    "native-android-core-aar" => "dist/native-android/sfiora-%{version}.aar",
    "native-android-ui-aar" => "dist/native-android/sfiora-ui-%{version}.aar",
    "native-android-maven-repository" => "dist/native-android/sfiora-%{version}-maven.zip",
    "native-ios-xcframework" => "dist/native-ios/sfiora-%{version}.xcframework.zip",
  }.freeze
  module_function

  def paths(version)
    raise Error, "Invalid native release version" unless
      version.is_a?(String) && version.match?(ReleasePolicy::SEMVER_PATTERN)
    ARTIFACTS.transform_values { |template| format(template, version: version) }
  end

  def validate!(manifest, version:, policy: ReleasePolicy.load(File.expand_path("../release-policy.json", __dir__)))
    fields = %w[androidMavenSigned artifacts commit dirty iosBinaryPromoted iosBinarySourceCommit plugin schemaVersion version]
    fields << "artifactReuse" if manifest.is_a?(Hash) && manifest.key?("artifactReuse")
    raise Error, "Native release manifest fields differ" unless manifest.is_a?(Hash) && manifest.keys.sort == fields.sort
    raise Error, "Native release identity differs" unless
      manifest.fetch("schemaVersion") == 2 && manifest.fetch("plugin") == policy.fetch("plugin") &&
        manifest.fetch("version") == version
    %w[commit iosBinarySourceCommit].each do |key|
      raise Error, "Invalid native #{key}" unless
        manifest.fetch(key).is_a?(String) && manifest.fetch(key).match?(/\A[0-9a-f]{40}\z/)
    end
    %w[dirty androidMavenSigned iosBinaryPromoted].each do |key|
      raise Error, "Invalid native #{key}" unless [true, false].include?(manifest.fetch(key))
    end
    artifacts = manifest.fetch("artifacts")
    raise Error, "Native artifacts must be an array" unless artifacts.is_a?(Array)
    artifacts.each do |entry|
      raise Error, "Native artifact fields differ" unless entry.is_a?(Hash) && entry.keys.sort == %w[bytes file sha256]
      raise Error, "Invalid native artifact byte count" unless entry.fetch("bytes").is_a?(Integer) && entry.fetch("bytes").positive?
      raise Error, "Invalid native artifact digest" unless
        entry.fetch("sha256").is_a?(String) && entry.fetch("sha256").match?(ReleasePolicy::SHA256_PATTERN)
    end
    expected = paths(version)
    raise Error, "Native artifact files differ" unless artifacts.map { |entry| entry.fetch("file") }.sort == expected.values.sort
    raise Error, "Native artifact roles differ from release policy" unless
      expected.keys.sort == NativeArtifactReuse.groups(policy: policy).values.flat_map { |group| group.fetch("roles") }.sort
    NativeArtifactReuse.validate!(manifest.fetch("artifactReuse"), manifest: manifest, policy: policy) if manifest.key?("artifactReuse")
    manifest
  rescue KeyError, ArgumentError, TypeError, NativeArtifactReuse::Error => error
    raise Error, "Invalid native manifest: #{error.message}"
  end

  def regular_path!(root, relative)
    root = Pathname.new(root)
    path = Pathname.new(relative)
    raise Error, "Unsafe native artifact path" unless !path.absolute? && path.cleanpath.to_s == relative &&
      path.each_filename.none? { |part| part == ".." }
    cursor = root
    path.each_filename do |part|
      cursor = cursor.join(part)
      raise Error, "Native artifact uses a symbolic link: #{cursor}" if cursor.symlink?
    end
    raise Error, "Native artifact is missing: #{cursor}" unless cursor.file?
    cursor
  end

  def verify_files!(manifest, root:)
    manifest.fetch("artifacts").each do |entry|
      path = regular_path!(root, entry.fetch("file"))
      raise Error, "Native artifact bytes differ: #{path}" unless
        path.size == entry.fetch("bytes") && Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
    end
  end

  def verify_candidate!(manifest, candidate:)
    raise Error, "Native manifest does not belong to the candidate" unless
      manifest.fetch("commit") == candidate.dig("source", "commit") &&
        manifest.fetch("dirty") == candidate.dig("source", "dirty") &&
        manifest.fetch("androidMavenSigned") == candidate.dig("qualifications", "androidMavenSigned")
    indexed = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
    candidate_entries = candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
    paths(candidate.fetch("version")).each do |role, relative|
      entry = candidate_entries.fetch(role)
      recorded = indexed.fetch(relative)
      raise Error, "Candidate native artifact differs: #{role}" unless
        File.basename(entry.fetch("file")) == File.basename(relative) &&
          %w[bytes sha256].all? { |field| recorded.fetch(field) == entry.fetch(field) }
    end
    raise Error, "An eligible candidate requires promoted iOS bytes" if
      candidate.fetch("acceptanceEligible") && manifest.fetch("iosBinaryPromoted") != true
  rescue KeyError => error
    raise Error, "Invalid native candidate binding: #{error.message}"
  end

  def verify_reuse!(manifest, root:)
    return unless manifest.key?("artifactReuse")
    NativeArtifactReuse.verify_inputs!(manifest.fetch("artifactReuse"), root: root, commit: manifest.fetch("commit"))
  rescue NativeArtifactReuse::Error => error
    raise Error, error.message
  end

  def verify_ios!(manifest, root:, archive:)
    raise Error, "iOS binary was not promoted" unless manifest.fetch("iosBinaryPromoted") == true
    root = Pathname.new(root)
    source = manifest.fetch("iosBinarySourceCommit")
    GitInputDigest.ancestor!(root, source, manifest.fetch("commit"))
    digest = NativeInputDigest.digest(root, source)
    raise Error, "iOS inputs changed since the binary was built" unless
      NativeInputDigest.digest(root, manifest.fetch("commit")) == digest && NativeInputDigest.digest(root) == digest
    output, error, status = Open3.capture3(
      "bash", root.join("scripts/verify-ios-xcframework-provenance.sh").to_s,
      archive.to_s, manifest.fetch("version"), digest, source
    )
    raise Error, "iOS binary provenance differs: #{error.strip.empty? ? output.strip : error.strip}" unless status.success?
    true
  rescue GitInputDigest::Error, KeyError => error
    raise Error, "Invalid iOS provenance: #{error.message}"
  end
end
