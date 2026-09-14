# Sfiora

[简体中文](README.md)

Sfiora is a general-purpose NFC reader and writer for Android, iOS, React Native,
and UniApp. It provides foreground tag discovery, NDEF reading, verified writes,
and marker-based preservation or initialization.

Your application chooses the data, its meaning, and its storage. Sfiora handles
NFC operations without depending on a login, identity, or other business model.

## Capabilities and boundaries

- Read tag technologies, available identifiers, and NDEF content, including
  original bytes and decoded common records.
- Write complete NDEF messages containing Text, URI, MIME, and External Type records.
- Read back immediately and compare the complete message bytes before reporting
  a successful write.
- Preserve messages containing an application marker; otherwise write and verify
  the supplied initialization message.
- Process-wide read/write exclusion, cancellation, timeouts, state queries, and
  structured errors.
- A headless Android core with optional managed panels; system NFC panels on iOS.

Writing requires a tag that already supports NDEF, is writable, and has enough
capacity. Sfiora does not format tags, permanently lock them, change passwords,
clone access cards, emulate cards, or expose arbitrary APDU/private-block writes.
A reported tag technology does not imply support for all of its commands.

NFC operations require a physical device with suitable NFC hardware and tags.
Simulators can support UI/build development, but cannot perform real NFC reads
or writes. Identifiers and available details depend on the device, OS, tag, and
reading mode.

## Platforms and distribution

| Platform | Distribution and guide | Minimum requirements |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.github.sandroxy/sfiora), `io.github.sandroxy:sfiora`; optional `sfiora-ui` | API 21 |
| iOS | [Swift Package](https://github.com/sandroxy/sfiora), product `Sfiora` | iOS 13 |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/sfiora), `@sandrox/sfiora`; [guide](adapters/react-native/README.md) | RN 0.76+; OS minimums also depend on the host |
| Classic uni-app legacy | Nativeplugin ZIP from GitHub Releases; [guide](adapters/uniapp/README.md) | HBuilderX 5.24, Android API 21 / iOS 13 |
| Classic uni-app UTS | [DCloud Marketplace](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora), `Sandrox-Sfiora`; [guide](adapters/uniapp/README.md) | HBuilderX 5.24, Android API 21 / iOS 13 |
| uni-app x | [The same Marketplace UTS package](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora), Vapor; [guide](adapters/uniapp/README.md) | HBuilderX 5.24, Android API 23 / iOS 15 |

Consult each channel for its published versions. See [CHANGELOG.md](CHANGELOG.md)
for version history and [GitHub Releases](https://github.com/sandroxy/sfiora/releases)
for offline AARs, XCFrameworks, RN packages, and UNI ZIPs. Replace `<version>` in
examples with your selected public version.

## Native integration

On Android, add `io.github.sandroxy:sfiora:<version>` from Maven Central, plus
`sfiora-ui` at the same version for managed panels. The [Android guide](native/android/README.md)
covers complete Activity examples, panels, configuration, results, and errors.

On iOS, add `https://github.com/sandroxy/sfiora.git` in Xcode, select a public
version, and link the `Sfiora` product. The [iOS guide](native/ios/README.md)
covers signing, permissions, read/write examples, and system session lifecycle.

RN and UNI packages already include the required native runtimes; their hosts
do not need a separate Maven or Swift Package dependency. Each platform guide
covers its own installation and lifecycle requirements.

## Results and preservation rules

Native `NdefRecord.text`, `uri`, `mime`, and `external` factories correspond to
the bridge's four record kinds. Native callers supply `byte[]` / `Data`; RN/UNI
represent binary fields as Base64. A Text record's language code is metadata;
read the decoded `text` / `decodedText` rather than treating the raw payload as
plain text.

After discovery, check NDEF status and read errors before interpreting business
content. A missing field, failed read, or discovered tag without NDEF is not
proof of an empty tag.

| Operation | Treatment of existing content | Successful outcome |
| --- | --- | --- |
| Replacement write | Replaces the entire message | Matching read-back bytes, `verified: true` |
| Initialization with a matching marker | Preserves the message; does not compare or update marker payload | `preserved`, no write |
| Initialization without a matching marker | Replaces the message, including any unrelated content | `initialized`, written and verified |

The initialization message must contain exactly one External Type record
matching the marker's domain/type; Sfiora does not insert it. Replace
`example.com:initialized` with your application's lowercase convention. An
unreadable existing message is not treated as empty, and initialization does
not format a factory tag.

A marker is a preservation convention, not a physical write lock, password, or
identity check. Other writers can overwrite it. Identity validation,
authorization, encryption, and data formats belong to the application.

Writes do not have transaction rollback. Cancellation, timeout, loss of contact,
or read-back failure after writing starts can leave changed, partial, or empty
content. Only a verified write reports write success. Read again after a failure
to establish the tag's actual state.

## Sessions, errors, and troubleshooting

Start only one read/write operation at a time. Disable actions while a call is
pending or the native session remains active; iOS may remain busy while closing.
RN/UNI expose `isScanning()` / `isWriting()` and bounded `waitForIdle()`;
native clients expose their corresponding states. A cancellation request returning does not mean the panel
has disappeared; still handle the original operation's result.

Branch on stable error codes and keep native errors for diagnosis. `recoverable`
is a retry hint, not a guarantee that a tag was unchanged. Native APIs, options,
and errors are in the [Android guide](native/android/README.md)
and [iOS guide](native/ios/README.md). Bridge details are in the [RN guide](adapters/react-native/README.md)
and [UNI guide](adapters/uniapp/README.md); shared fields are defined in
[contract/types.ts](contract/types.ts).

- Missing module: add native dependencies and rebuild. Expo Go and standard
  bases without the plugin cannot run its native code.
- iOS session cannot start: check the usage description, NFC capability, signed
  entitlements, and provisioning profile.
- Android opens a system tag page: start the operation before presenting a tag;
  idle NFC Intent handling is the host's responsibility.
- Read succeeds but write fails: check NDEF support, writability, capacity, and
  stable contact throughout the operation.
- Still busy after cancellation: wait for actual idle state; do not force-enable
  actions after an arbitrary delay.

`waitForIdle()` observes this bridge instance and defaults to 5 seconds. A
`SESSION_CLOSE_TIMEOUT` rejection neither cancels the operation nor releases
its resources; keep actions gated by actual state and allow a state refresh.
Native cleanup may deliver a pending result after a five-second grace period
while remaining busy until the actual close. Android reads and initialization
checks use live NDEF data; an empty live message never falls back to discovery cache.

## Maintenance and support

Local setup, source tests, and build-directory ownership are in
[DEVELOPMENT.md](DEVELOPMENT.md); candidate and publication procedures are in
[RELEASING.md](RELEASING.md). Report
issues with the version, platform, host type, operation, error code, and relevant
native error through [Issues](https://github.com/sandroxy/sfiora/issues), removing
private tag data. Report security issues according to [SECURITY.md](SECURITY.md).

## Privacy and license

Sfiora does not upload tag contents to the author's servers, include analytics
or advertising SDKs, or persist application data for the host. The caller owns
data generation, validation, writing, and any subsequent application storage.

Released under the [Apache License 2.0](LICENSE).
