# Releasing Sfiora

Sfiora separates a product version from the identity of one concrete build.
`plugin.json` declares the next product version. A version is not stable until
its exact public files are locked by the consumer repository after publication.

## Release states

- `dist/native-*`, `dist/react-native`, and `dist/uniapp` are mutable build
  workspaces. Their filenames are not acceptance evidence.
- `dist/rehearsals/<version>/<candidate-id>/` contains a snapshot made from a
  dirty source tree or unsigned Maven output. It can test the pipeline but can
  never be accepted or published.
- `dist/candidates/<version>/<candidate-id>/` contains an immutable, clean,
  signed, acceptance-eligible artifact set. Its `candidate.json` binds every
  file to its byte length, SHA-256, source commit, artifact-set digest, and
  candidate id.
- A public stable release exists only after those exact candidate bytes are
  published. The separate `integrated-plugins` repository then pins their
  public URLs and hashes in `verification/stable-lock.json`.

Never use a bare version number to choose local bytes and never overwrite a
published version. A rejected build keeps its own candidate id; rebuild the
same still-unpublished product version and obtain a different id.

## Build and snapshot

Start from a clean commit whose `plugin.json` version has no local or `origin`
tag. Formal Android output requires `SFIORA_SIGNING_KEY`. The public Swift
Package is binary, so iOS uses a two-commit handoff: build the XCFramework once
from the clean source commit, then record those exact bytes in `Package.swift`.

```sh
export SFIORA_IOS_SOURCE_COMMIT="$(git rev-parse HEAD)"
./scripts/package-native-ios.sh
export SFIORA_IOS_ARCHIVE="$(pwd)/dist/native-ios/sfiora-<version>.xcframework.zip"
export SFIORA_IOS_SHA256="$(swift package compute-checksum "${SFIORA_IOS_ARCHIVE}")"
```

Update the binary target URL and checksum in `Package.swift`, run the metadata
checks, and commit that release metadata without changing `native/ios` or
the other binary inputs (`LICENSE`, `plugin.json`, `package-native-ios.sh`, or
`release-common.sh`). Then promote the already-built archive while preparing
the complete native release:

```sh
SFIORA_IOS_ACCEPTED_XCFRAMEWORK_ZIP="${SFIORA_IOS_ARCHIVE}" \
SFIORA_IOS_ACCEPTED_XCFRAMEWORK_SHA256="${SFIORA_IOS_SHA256}" \
SFIORA_IOS_ACCEPTED_SOURCE_COMMIT="${SFIORA_IOS_SOURCE_COMMIT}" \
  ./scripts/prepare-native-release.sh
./scripts/package-react-native.sh
./scripts/package-uniapp.sh
./scripts/prepare-release-candidate.sh
```

The last command prints the absolute `candidate.json` path. It validates the
native manifest, checksum sidecars, adapter identities, embedded-native
provenance, and the unchanged iOS source lineage before copying the complete
set into `dist/candidates`. A locally rebuilt iOS archive that was not promoted
with all three accepted-binary values can only produce a rehearsal.

[`release-policy.json`](release-policy.json) is Sfiora's machine-readable
release contract. Candidate creation and the publication gate require an exact
match for the product id, source repository, qualification fields, artifact
roles, and automated/manual acceptance matrix. It contains no sibling-product
catalog; every plugin owns its own independent policy.

For pipeline work only, `--allow-dirty` and `--allow-unsigned` produce a
`rehearsal`. The state is derived from the actual source and signing evidence;
the flags do not make an ineligible build acceptable.

## Consumer acceptance

In a clean checkout of `integrated-plugins`, execute every automated target
declared by the candidate. Each command writes immutable evidence bound to the
candidate manifest and verifier commit:

Every candidate-declared target runs in a Sfiora-only consumer. Shared React
Native and classic UniApp catalog sources are used to generate ignored isolated
hosts, so another plugin's version or availability cannot influence a Sfiora receipt.
The combined-showcase smoke is stable-only and never participates in Sfiora
publication acceptance.

```sh
./verification/run-acceptance.rb \
  --candidate /absolute/path/to/candidate.json \
  --target android
# Repeat for ios, react-native-android, react-native-ios, and uniapp.
```

Complete every declared NFC device target against the same staged files. Then
record each manual result by target; omitted targets remain `pending`, and a
receipt becomes `accepted` only when every declared automated and manual target
is `passed`:

```sh
./verification/record-acceptance.rb \
  --candidate /absolute/path/to/candidate.json \
  --manual native-android-nfc-device=passed \
  --manual native-ios-nfc-device=passed \
  --manual react-native-android-nfc-device=passed \
  --manual react-native-ios-nfc-device=passed \
  --manual uniapp-android-nfc-device=passed \
  --manual uniapp-ios-nfc-device=passed
```

Commit the receipt in `integrated-plugins`. A `pending` receipt may document
unfinished device work but cannot open the publication gate.

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

After every public channel is available, update the Sfiora entry in
`integrated-plugins/verification/stable-lock.json` with the public URLs, byte
lengths, and SHA-256 values. Only that change makes Sfiora the default stable
demo dependency.
