# @sandrox/sfiora

Read NFC tags, replace NDEF messages with read-back verification, and preserve
previously initialized tags on Android and iOS. The package includes the native
Sfiora runtimes and supports React Native's legacy architecture and TurboModules.

## Install

```sh
npm install @sandrox/sfiora
```

Use a native application or a [development build](https://docs.expo.dev/develop/development-builds/introduction/).
Sfiora does not run in Expo Go, on the web, or as a JavaScript-only update to an
app that does not already contain its native module. NFC operations require a
physical device with compatible NFC hardware.

### Expo

Add the config plugin to `app.json`, merging it with your existing configuration:

```json
{
  "expo": {
    "plugins": [
      ["@sandrox/sfiora", {
        "iosUsageDescription": "Read and write NFC tags selected by you."
      }]
    ]
  }
}
```

The plugin adds the Android NFC permission and optional hardware declaration,
the iOS usage description, and the `TAG` reader-session entitlement. Enable
**Near Field Communication Tag Reading** for your Apple App ID and use a
provisioning profile that includes that capability.

Regenerate the native configuration and rebuild for your connected device:

```sh
npx expo prebuild
npx expo run:android --device
# Or, on macOS:
npx expo run:ios --device
```

Applications using CNG may also use EAS Build. Applications maintaining their
own native projects should review the generated changes or configure those
projects directly. Updating the plugin configuration requires a new native build.

Optional config-plugin properties are `iso7816ApplicationIdentifiers` (an array
of hexadecimal AIDs, each 10–32 characters with even length) and
`felicaSystemCodes` (an array of four-character hexadecimal system codes).
Supply identifiers belonging to the tags your application supports. These
properties configure iOS discovery; they do not add an APDU or FeliCa command API.

### React Native with native projects

The module is autolinked. Run `bundle exec pod install` in your `ios` directory,
then rebuild the Android/iOS application. The package already includes Sfiora's
native binaries; a separate Maven or Swift Package dependency is unnecessary.

Android merges `android.permission.NFC` and an optional `android.hardware.nfc`
feature from the library manifest. NFC does not require a runtime permission
dialog; the user may still need to enable NFC in system settings.

For iOS, add `NFCReaderUsageDescription` to the app's `Info.plist` and enable
**Near Field Communication Tag Reading** in **Signing & Capabilities**. The
signed app's entitlements must contain:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```

Keep the App ID, signing profile, and entitlements consistent. FeliCa polling
also needs the applicable system codes in `Info.plist`.

## Read a tag

Call operations from user actions while the application is in the foreground.
Each scan completes with one result; it is not a continuous subscription.

```ts
import * as sfiora from '@sandrox/sfiora';

export async function readTag() {
  const capabilities = await sfiora.getCapabilities();
  if (!capabilities.supported || !capabilities.enabled) {
    throw new Error('NFC is unavailable or disabled on this device.');
  }
  try {
    return await sfiora.startScan({
      mode: 'automatic',
      timeoutMilliseconds: 30000,
    });
  } catch (error) {
    if (error instanceof sfiora.SfioraError && error.code === 'USER_CANCELLED') {
      return null;
    }
    throw error;
  }
}
```

The result includes `id`, `technologies`, `ndef`, and `warnings`. Decoded NDEF
values are in `tag.ndef?.records`: use `text`, `uri`, or `payloadBase64` as
appropriate. Check `ndef.status` and `ndef.readError` as well: discovering a tag
does not guarantee that its NDEF data was readable. Missing metadata must not
be treated as an empty business value.

`automatic` reads NDEF when available; `discover` returns tag information
without requesting NDEF. `ndef` requires NDEF and uses iOS's compatibility
reader, whose result can lack a tag identifier. Technology names, identifiers,
and optional details can differ between Android and iOS.

## Replace an NDEF message

The remaining examples use the same `sfiora` import. Invoke each function from
its own user action, and handle its rejected Promise at the call site.

```ts
export async function replaceTag() {
  const message: sfiora.NfcNdefMessageInput = {
    records: [{ kind: 'text', text: 'Hello from Sfiora', languageCode: 'en' }],
  };
  return await sfiora.writeNdef(message, { timeoutMilliseconds: 30000 });
}
```

This replaces the **whole NDEF message**, including all previous records.
The tag must already support NDEF, be writable, and have sufficient capacity.
The successful result has `verified: true`, `bytesWritten`, `recordCount`, and
the read-back `tag`. Verification compares the complete serialized NDEF bytes.

A write is not a transaction with rollback. If contact is lost, cancellation
occurs, or verification fails after writing begins, the tag may contain old,
new, incomplete, or empty data. Read the tag again before deciding what to do;
an error does not establish that its previous contents survived.

### Record types

`records` must be non-empty. These records can be used individually or together:

```ts
const textRecord: sfiora.NfcNdefRecordInput = {
  kind: 'text', text: '你好', languageCode: 'zh-Hans', encoding: 'UTF-8',
};
const uriRecord: sfiora.NfcNdefRecordInput = {
  kind: 'uri', uri: 'https://example.com',
};
const mimeRecord: sfiora.NfcNdefRecordInput = {
  kind: 'mime', mediaType: 'application/octet-stream', payloadBase64: 'AQID',
};
const externalRecord: sfiora.NfcNdefRecordInput = {
  kind: 'external', domain: 'example.com', type: 'initialized', payloadBase64: 'AQID',
};
```

Text records require a language code and default to UTF-8; UTF-16 is also
supported. The language code is NDEF metadata, not part of the decoded `text`.
A raw-payload viewer may show it next to the text. Use a URI record with a
scheme such as `https://` for a web address.

MIME and external payloads are bytes represented as Base64. `AQID` above
represents `01 02 03`; it does not write the four literal characters `AQID`.
Encode your application's bytes before calling. All record types also accept
an optional Base64 `identifierBase64`.

## Preserve or initialize

```ts
export async function initializeTag() {
  const marker: sfiora.NfcNdefExternalTypeMarker = {
    domain: 'example.com', type: 'initialized',
  };
  const message: sfiora.NfcNdefMessageInput = {
    records: [{
      kind: 'external',
      domain: marker.domain,
      type: marker.type,
      payloadBase64: 'AQID',
    }],
  };
  return await sfiora.initializeNdef(message, marker);
}
```

Choose a lowercase domain/type owned by your application; `example.com` is a
placeholder. The supplied message must contain **exactly one** external record
matching that marker. Sfiora does not insert a marker automatically.

- An existing record with the marker's domain/type returns `action: 'preserved'`.
  Nothing is written; `verified` and write-byte fields are absent. The existing
  payload is not compared with the supplied payload.
- Without that marker, the entire message is replaced and verified, returning
  `action: 'initialized'` and `verified: true`. This also overwrites non-empty
  messages belonging to a different marker.
- An unreadable existing message causes an error instead of being assumed
  empty. This operation does not format an unformatted factory tag.

This convention preserves marked content. It does not lock the tag or provide
authentication: another writer can replace its data, and copying the marker
does not prove an identity. Application validation, authorization, encryption,
and business data formats remain with the host.

## Cancellation and session state

```ts
export async function cancelCurrentOperation() {
  await sfiora.cancelScan();
  await sfiora.cancelWrite(); // Also cancels initializeNdef.
}

export async function isNfcBusy() {
  const scanning = await sfiora.isScanning();
  const writing = await sfiora.isWriting();
  return scanning || writing;
}
```

Cancellation calls acknowledge the request; they do not return the original
operation's result or promise that the system panel has disappeared. Handle
the original Promise rejection as well. Cancelling an inactive operation is
harmless.

Allow only one read/write action at a time, including across screens. Disable
both action buttons while a call is pending **or** either native state is true.
iOS can deliver a successful result while its system panel is still closing;
refresh the state until it becomes idle before enabling the next action.
Do not rely on a fixed delay or just the operation's `finally` block. If a state
query fails, display the error rather than assuming the session is idle.

When the screen owning an operation loses focus or unmounts, request its
cancellation and stop updating that screen from late results. Navigation can
leave the native Activity active, so app lifecycle cleanup alone does not
replace screen cleanup. Keep the app foregrounded and the tag still until the
operation finishes.

## Options and errors

| Scan option | Default | Meaning |
| --- | --- | --- |
| `mode` | `automatic` | `automatic`, `ndef`, or `discover` |
| `timeoutMilliseconds` | `30000` | Integer from `1000` to `60000` |
| `android.presentation` | `managed` | `none` disables the Android **scan** panel |
| `android.deepReadEnabled` | `false` | Optional read-only protocol probes on supported tags |
| `android.presenceCheckDelayMilliseconds` | `250` | Integer from `50` to `5000` |
| `ios.pollingTechnologies` | `['iso14443', 'iso15693']` | Non-empty list; `iso18092` additionally needs FeliCa configuration |
| `messages` | Built-in messages | Complete `NfcScanMessages` object for customized wording |

Write options are `timeoutMilliseconds` with the same range/default and a
complete `NfcWriteMessages` object. They do not accept scan-only options.
Android bridge writes use the managed panel; iOS always uses the system NFC
panel. Platform options apply on their named platform. Unknown fields and
invalid values are rejected with `INVALID_OPTIONS`; custom `messages` objects
must supply every required non-empty field. See the shipped
[TypeScript declarations](index.d.ts) and `contract/types.ts` for field names.

`SfioraError` exposes `code`, `message`, `recoverable`, and optional
`nativeError`. Branch on `code`; native messages may vary by device and OS.

| Code | Suggested handling |
| --- | --- |
| `NFC_UNSUPPORTED`, `NFC_DISABLED` | Check device support or ask the user to enable NFC |
| `SCAN_BUSY`, `WRITE_BUSY` | Let the current session finish; do not enqueue automatic retries |
| `USER_CANCELLED` | End the local interaction normally |
| `SCAN_TIMEOUT`, `WRITE_TIMEOUT`, `TAG_LOST` | Ask the user to retry with stable tag contact |
| `UNSUPPORTED_TAG`, `TAG_READ_ONLY`, `NDEF_CAPACITY_EXCEEDED` | Use a suitable formatted, writable tag or smaller message |
| `READ_FAILED` | Inspect the read error; do not interpret it as an empty tag |
| `WRITE_FAILED`, `WRITE_VERIFICATION_FAILED` | Read again to establish the tag's actual state |
| `INVALID_OPTIONS` | Correct the request before retrying |
| `INTERNAL_ERROR` | Check native linking, app lifecycle, and the native error details |

`recoverable` is a retry hint, not a guarantee that a write left the tag unchanged.
The same write-state uncertainty applies to timeout, cancellation, and tag loss.

## Compatibility, privacy, and support

The package requires Node.js 18+ and React Native 0.76+. The native Sfiora cores
target Android API 21 and iOS 13; the host must also meet its React Native and
Expo requirements. For example, [React Native 0.76 requires Android API 24 and iOS 15.1](https://reactnative.dev/blog/2024/10/23/release-0.76-new-architecture#updates-to-minimum-ios-and-android-sdk-requirements).
Do not lower the host's deployment target to the core minimum.

Sfiora does not format tags, change passwords, permanently lock tags, clone
access cards, emulate cards, or expose arbitrary APDU/private-block writes.
Tag technologies and read-only details do not imply support for all operations
on that technology. It does not upload tag contents, include analytics, or
interpret application-specific payloads. The host controls storage and use of
returned data.

For linking errors, rebuild the native app after installation. For iOS session
errors, check the usage description, signed entitlement, and signing profile.
When reporting a problem, include the package version, OS/device, operation,
error code, and relevant native error, omitting private tag contents.

[Source and issues](https://github.com/sandroxy/sfiora) ·
[Release history](https://github.com/sandroxy/sfiora/blob/main/CHANGELOG.md) ·
[Apache License 2.0](https://github.com/sandroxy/sfiora/blob/main/LICENSE)
