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
- Prevent overlapping reads and writes within the app process, with
  cancellation, timeouts, state queries, and structured errors.
- A headless Android core with optional managed panels; system NFC panels on iOS.

## Platforms and distribution

| Platform | Recommended channel | Integration |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.github.sandroxy/sfiora) · `io.github.sandroxy:sfiora` | [Android guide](native/android/README.md), with optional managed panels and offline AAR mirrors |
| iOS | [Swift Package](https://github.com/sandroxy/sfiora) | [iOS guide](native/ios/README.md), with a checksum-verified XCFramework |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/sfiora) · `@sandrox/sfiora` | [RN guide](adapters/react-native/README.md), with Android/iOS native runtimes included |
| UniApp | [DCloud Marketplace](https://ext.dcloud.net.cn/plugin?name=Sandrox-Sfiora) | [UNI guide](adapters/uniapp/README.md), for classic uni-app and uni-app x Vapor Android/iOS Apps |

See [GitHub Releases](https://github.com/sandroxy/sfiora/releases) and
[CHANGELOG.md](CHANGELOG.md) for version history, checksums, and offline artifacts.
Consult each channel for its published versions and each platform guide for
minimum versions, permissions, and host requirements. The UNI guide also explains
how to choose between the shared UTS package and the legacy native plugin.

## Native integration

On Android, add `io.github.sandroxy:sfiora:<version>` from Maven Central,
replacing `<version>` with your selected public version. Add `sfiora-ui` at
the same version for managed panels. The [Android guide](native/android/README.md)
covers complete Activity examples, panels, configuration, results, and errors.

On iOS, add `https://github.com/sandroxy/sfiora.git` in Xcode, select a public
version, and link the `Sfiora` product. The [iOS guide](native/ios/README.md)
covers signing, permissions, read/write examples, and system session lifecycle.

RN and UNI packages already include the required native runtimes; their hosts
do not need a separate Maven or Swift Package dependency. Each platform guide
covers its own installation and lifecycle requirements.

## Read/write semantics

NFC operations require a physical NFC-capable device and suitable tags. Writing
requires a tag that already supports NDEF, is writable, and has enough capacity.
Discovering a tag does not guarantee that its NDEF content is readable or writable.

| Operation | Treatment of existing content | Successful result |
| --- | --- | --- |
| Replacement write | Replaces the entire NDEF message | Matching read-back bytes, `verified: true` |
| Initialization: matching marker exists | Preserves the message without comparing or updating marker payload | `preserved`, no write |
| Initialization: no matching marker | Replaces the entire message, including unrelated content | `initialized`, written and verified |

Initialization matches an application-defined External Type marker. The supplied
message must contain exactly one matching record; unreadable content is never
assumed empty. Each platform guide covers record formats, results, and examples.

Writes have no transaction rollback. After cancellation, timeout, failed
verification, or lost contact, read again to establish the actual contents.
A marker provides neither locking nor authentication. Sfiora does not format tags, permanently lock them,
change passwords, clone access cards, emulate cards, or expose arbitrary
APDU/private-block writes.

## Sessions and errors

Start one read/write operation at a time. After success, failure, or a
cancellation request returns, wait for native resources to be released before
enabling the next action. RN/UNI provide bounded `waitForIdle()` for this purpose.
An idle-wait timeout does not mean the native session has closed.

Lifecycle handling, error codes, and troubleshooting are in the
[Android guide](native/android/README.md), [iOS guide](native/ios/README.md),
[RN guide](adapters/react-native/README.md), and [UNI guide](adapters/uniapp/README.md).

## Maintenance and support

Local setup, source tests, and build-directory ownership are in
[DEVELOPMENT.md](DEVELOPMENT.md); candidate and publication procedures are in
[RELEASING.md](RELEASING.md). Report
issues with the version, platform, host type, operation, error code, and relevant
native error through [Issues](https://github.com/sandroxy/sfiora/issues), removing
private tag data. Report security issues according to [SECURITY.md](SECURITY.md).

## Privacy and license

Sfiora reads, processes, and returns tag data on the device, and writes the
contents supplied by the caller. It does not upload tag contents to the author's
servers, include analytics or advertising SDKs, or persist tag contents on the
host device. The caller is responsible for application-specific validation and
subsequent storage.

Released under the [Apache License 2.0](LICENSE).
