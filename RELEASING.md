# Releasing Sfiora

Sfiora separates a product version from the identity of one concrete build.
`plugin.json` declares the next product version. A version is not stable until
its exact public files are locked by the consumer repository after publication.

## Release states

- Platform directories under `dist/` contain the release files. Their
  filenames are not acceptance evidence.
- `dist/candidate.json` records the current set using paths relative to
  `dist/`, binding every file to its byte length, SHA-256, source commit,
  artifact-set digest, and candidate id. It does not copy the artifacts.
- Clean, signed output with verified provenance has state `candidate`.
  A dirty, unsigned, or unpromoted iOS build uses the same manifest with state
  `rehearsal`; it can test the pipeline but cannot be accepted or published.
- A public stable release exists only after those exact candidate bytes are
  published. The separate `integrated-plugins` repository then pins their
  public URLs and hashes in `verification/stable-lock.json`.

Never use a bare version number to choose local bytes and never overwrite a
published version. Rebuilding a rejected, still-unpublished version replaces
the current manifest; changed bytes or a new source commit change its candidate
id and invalidate previous acceptance results.

## Documentation

The root Chinese and English READMEs are consumer installation guides. Keep
their platform coverage, native examples, and behavior descriptions aligned.
Adapter READMEs describe complete integration, request/result semantics,
lifecycle handling, and platform limits. Public documentation must follow the
shipped APIs and must not depend on a business host or an internal test page.

Keep product-version literals in `plugin.json`, package manifests, changelogs,
and release records; use `<version>` in stable installation examples. Framework
and operating-system requirements remain explicit in consumer documentation.
Maintain release notes once in `CHANGELOG.md`. Packaging copies that file into
RN and legacy packages as `CHANGELOG.md`, and into the UTS package as
`changelog.md`. The UTS `readme.md` is copied from `adapters/uniapp/README.md`;
edit its source rather than a generated consumer or a second market-only guide.

Finalize packaged documentation before recording a candidate. Documentation
inside an npm tarball or UNI ZIP is part of that artifact's identity. Updating
it requires new adapter packages, a new candidate, and matching automated
consumer results. Native artifacts with unchanged inputs may be reused through
the existing reuse workflow. Additional device checks follow actual executable
changes and risks; do not discard previous physical test observations solely
because wording changed or copy an old acceptance receipt to a new candidate.

After publication, ordinary documentation corrections can be committed to the
default branch. They must not move a public tag, replace release files, or
rebuild an already published version. Registry documentation embedded in a
package remains the copy shipped with that version.

## Build and snapshot

Start from a clean commit whose `plugin.json` version has no local or `origin`
tag, with packaged documentation finalized. Formal Android output requires
`SFIORA_SIGNING_KEY`. The public Swift Package is binary, so iOS uses a
two-commit handoff: build the XCFramework once
from the clean source commit, then record those exact bytes in `Package.swift`.

```sh
export SFIORA_IOS_SOURCE_COMMIT="$(git rev-parse HEAD)"
./scripts/package-native-ios.sh
export SFIORA_IOS_ARCHIVE="$(pwd)/dist/native-ios/sfiora-<version>.xcframework.zip"
export SFIORA_IOS_SHA256="$(swift package compute-checksum "${SFIORA_IOS_ARCHIVE}")"
```

Update the binary target URL and checksum in `Package.swift`, run the metadata
checks, and commit that release metadata without changing the inputs listed in
[`native-input-digest.rb`](scripts/native-input-digest.rb). Then promote the
already-built archive while preparing the complete native release:

```sh
SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP="${SFIORA_IOS_ARCHIVE}" \
SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256="${SFIORA_IOS_SHA256}" \
SFIORA_IOS_ACCEPTED_SOURCE_COMMIT="${SFIORA_IOS_SOURCE_COMMIT}" \
  ./scripts/prepare-native-release.sh
./scripts/package-react-native.sh
./scripts/package-uniapp.sh
./scripts/package-uniapp-uts.sh
./scripts/verify-react-native.sh
./scripts/verify-uniapp.sh
./scripts/verify-uniapp-uts.sh
./scripts/prepare-release-candidate.sh
```

The last command prints the absolute `dist/candidate.json` path. It validates the
native manifest, checksum sidecars, adapter identities, embedded-native
provenance, and the unchanged iOS source lineage before recording the existing
files. A locally rebuilt iOS archive that was not promoted with all three
accepted-binary values can only produce a rehearsal.

Successful recording removes older versioned files only from the selected
filename families. It retains selected files, the current version, and the
latest canonical local Git tag's version. Unknown files, symbolic links, and
historical self-contained candidate directories remain untouched; those older
candidates remain readable. A tag is a local retention boundary, not proof of
publication to every registry.

When a rejected candidate's native inputs are unchanged, reuse those exact
bytes before overwriting any of its files or repackaging adapters:

```sh
ruby scripts/reuse-native-artifacts.rb --candidate "$(pwd)/dist/candidate.json" --plan
./scripts/prepare-native-release.sh \
  --reuse-candidate "$(pwd)/dist/candidate.json" --reuse android --reuse ios \
  --signature-fingerprint "<existing-public-key-fingerprint>"
```

Select only the unchanged groups; other groups are rebuilt. Existing artifacts
at their destination are verified in place. Android reuse verifies signatures
with the existing public key; rebuilding Android still requires signing
credentials. Then package and verify the adapters and record the new candidate
as above. Native reuse does not carry forward acceptance results.

[`release-policy.json`](release-policy.json) is Sfiora's machine-readable
release contract. Candidate creation and the publication gate require an exact
match for the product id, source repository, qualification fields, artifact
roles, and automated/manual acceptance matrix. It contains no sibling-product
catalog; every plugin owns its own independent policy.

For pipeline work only, `--allow-dirty` and `--allow-unsigned` produce a
`rehearsal`. The state is derived from the actual source and signing evidence;
the flags do not make an ineligible build acceptable.

## Consumer acceptance

In a clean checkout of `integrated-plugins`, execute every automated target in
the candidate. Each isolated host must consume the final package bytes.
Record each declared NFC device target as `passed`, `pending`, or `failed`
based on actual testing; keep commands and scenarios in the test repository.
Further interaction checks follow changed behavior and known risks.

Generated receipts stay in the test repository's ignored output directory.
The publication gate requires passing automated results and device statuses
for the exact candidate. The publisher reviews actual NFC behavior and known
issues before deciding to release.

## Tag and publish

After acceptance, create one annotated tag on the candidate's recorded source
commit. Do not rebuild after tagging.

```sh
git tag -a "<version>" -m "Sfiora <version>"
./scripts/verify-publish-candidate.rb \
  --candidate /absolute/path/to/candidate.json \
  --acceptance /absolute/path/to/accepted-receipt.json
```

The gate requires a clean worktree, an annotated version tag pointing to the
candidate source commit, a clean accepted verifier receipt, and byte-for-byte
matching artifacts. Upload or publish only the paths printed by the gate.
`publish-accepted.rb` repeats this gate immediately before each channel operation:

```sh
./scripts/publish-accepted.rb \
  --candidate /absolute/path/to/candidate.json \
  --acceptance /absolute/path/to/accepted-receipt.json \
  --channel github
# Other channels: npm, maven, uniapp.
```

Push the annotated tag before GitHub publication. Maven requires
`SFIORA_CENTRAL_TOKEN` and final publication of the validated deployment in the
Central portal. The `uniapp` channel identifies the accepted UTS archive and
its HBuilderX publication route: open the existing consumer project that
installed this archive, right-click `uni_modules/Sandrox-Sfiora`, and choose
**发布到插件市场**. Use the packaged `readme.md`; no second manual copy is needed.
Keep executable files unchanged through publication. HBuilderX may write back
market metadata and changelog dates. Verify the public installation separately
in the test repository. The legacy ZIP is a compatibility/offline artifact.
Attach both accepted ZIPs to the canonical GitHub Release without repacking.

After every public channel is available, update the Sfiora entry in
`integrated-plugins/verification/stable-lock.json` with the public URLs, byte
lengths, and SHA-256 values. Only that change makes Sfiora the default stable
demo dependency.
