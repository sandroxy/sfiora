# @sandrox/sfiora

Read NFC tags, replace NDEF messages with read-back verification, and preserve
messages containing an application marker on Android and iOS. The package
includes the native Sfiora runtimes and supports React Native's legacy
architecture and TurboModules.

## Requirements

The package requires Node.js 18+ and React Native 0.76+. The native Sfiora cores
target Android API 21 and iOS 13; the host must also meet its React Native and
Expo requirements. For example, [React Native 0.76 requires Android API 24 and iOS 15.1](https://reactnative.dev/blog/2024/10/23/release-0.76-new-architecture#updates-to-minimum-ios-and-android-sdk-requirements).
Do not lower the host's deployment target to the core minimum.

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

## API overview

Every method returns a Promise. Request fields and result types are defined in
[index.d.ts](index.d.ts); the following sections show complete calls.

| Method | Purpose |
| --- | --- |
| `getCapabilities` | Query NFC support and whether it is enabled |
| `startScan` | Read one tag snapshot |
| `writeNdef` | Replace and verify a complete NDEF message |
| `initializeNdef` | Preserve matching content or write and verify the initial message |
| `cancelScan` | Request cancellation of the current scan |
| `cancelWrite` | Request cancellation of a write or initialization |
| `isScanning` | Query native read activity |
| `isWriting` | Query native write activity |
| `waitForIdle` | Wait for this bridge instance to become idle, with a deadline |
| `acquireForegroundDispatch` / `releaseForegroundDispatch` | Request/release Android foreground tag handling for one owner |
| `getForegroundDispatchState` | Query native foreground dispatch state and diagnostics |
| `getPresentationState` | Query visible managed Android panels; iOS reports unsupported |
| `waitForPresentationEnd` | Wait for captured Android panels to close; iOS rejects as unsupported |

## Read a tag

Call operations from user actions while the application is in the foreground.
Each scan completes with one result; it is not a continuous subscription.
The examples below are helper functions in a TypeScript module, not a complete
screen. The screen handles their results and rejected Promises, and owns button
state and [cancellation when it loses focus](#cancellation-and-session-state).

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
appropriate. When `ndef` is present, check its `status` and `readError` as well:
discovering a tag does not guarantee that its NDEF data was readable. Missing
metadata must not be treated as an empty business value.

When no identifier is available, `id` is still present with empty `hex` and
`base64` strings and `length: 0`.

Android reads and initialization use live NDEF data. When the current message
is empty, Sfiora does not substitute data cached when the tag was discovered.

`automatic` reads NDEF when available; `discover` returns tag information
without requesting NDEF. `ndef` requires NDEF and uses iOS's compatibility
reader, whose result can lack a tag identifier. Technology names, identifiers,
and optional details can differ between Android and iOS.

## Replace an NDEF message

The remaining examples use the same `sfiora` import.

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
wait for actual idle before enabling the next action. The following fragment
shows the wait; connect success and failure to your screen's button and error
state:

```ts
try {
  await sfiora.waitForIdle({ timeoutMilliseconds: 5000 });
} catch (error) {
  // Display the error; keep actions disabled until a state refresh confirms idle.
}
```

`waitForIdle()` checks this bridge instance, resolves with no value, and never
cancels a request or reserves the next session. `timeoutMilliseconds` is an
integer from 1 to 60000 (default 5000). `SESSION_CLOSE_TIMEOUT` also covers a
state query that never answers. Query errors propagate; they are not idle.
If native closing takes over five seconds, a pending result can arrive while
its session is still busy.
Do not rely on a fixed delay or just the operation's `finally` block. If a state
query fails, display the error rather than assuming the session is idle.

When the screen owning an operation loses focus or unmounts, request its
cancellation and stop updating that screen from late results. Navigation can
leave the native Activity active, so app lifecycle cleanup alone does not
replace screen cleanup. Keep the app foregrounded and the tag still until the
operation finishes.

## Optional foreground tag handling

Foreground-dispatch and panel-completion APIs require Sfiora 1.2.0 or newer in
both the JS package and the rebuilt native app.

By default, Sfiora leaves idle tag dispatch to the system. Enable this feature
when a tag may stay near the phone while your NFC screen is idle.
Android can otherwise open another tag-handling screen between your operations.
Foreground dispatch receives and ignores these idle tags; it does not start a
read, grant a read/write reservation, or affect background tag handling.

Acquire a unique `ownerId` while the screen needs this behavior and release it
when the screen loses focus. Repeated acquisition of one ID is idempotent;
release removes only that owner's request. Releasing an unknown ID is harmless.
IDs contain 1–128 ASCII letters, digits, `.`, `_`, `:`, or `-`, starting with a
letter or digit. A native controller
can hold up to 128 distinct owners. Invalid IDs reject with `INVALID_OPTIONS`.

The following hook handles acquisition and cleanup for both RN architectures.
Pass the screen's actual navigation focus, not just its mounted state. Keep
`onState` and `onError` stable with `useCallback`; they display state and errors
in your screen. Operation cancellation remains the screen's responsibility.

```ts
import { useEffect } from 'react';
import { Platform } from 'react-native';
import * as sfiora from '@sandrox/sfiora';

let foregroundOwnerSequence = 0;

export function useNfcForegroundDispatch(
  isFocused: boolean,
  onState: (state: sfiora.NfcForegroundDispatchState) => void,
  onError: (error: unknown) => void,
) {
  useEffect(() => {
    if (!isFocused || Platform.OS !== 'android') return;
    const ownerId = `nfc-screen:${Date.now()}:${++foregroundOwnerSequence}`;
    let active = true;
    const report = (error: unknown) => {
      if (active) onError(error);
      else console.error('NFC foreground cleanup failed', error);
    };

    void sfiora.acquireForegroundDispatch(ownerId).then(async state => {
      if (active) onState(state);
      else await sfiora.releaseForegroundDispatch(ownerId);
    }).catch(report);

    return () => {
      active = false;
      void sfiora.releaseForegroundDispatch(ownerId).catch(report);
    };
  }, [isFocused, onState, onError]);
}
```

The extra release after a late acquisition is intentional and harmless: it
always uses that effect's captured ID. It cannot release the next screen's ID.
App pause/resume and NFC setting changes are handled natively while requests
are held; bridge destruction releases all of that bridge's requests.
No additional Expo plugin, receiver, or native module is needed.

A resolved acquisition returns `{ platform, revision, state, error }`, even
when dispatch is not active. Inspect `state`: `active` means registered,
`paused` means no resumed Activity, `nfcDisabled` means NFC is off, and
`unavailable` means no NFC hardware. `disabled` means no requests remain;
`failed` includes a native diagnostic in `error`. Query
`getForegroundDispatchState()` again on app resume or return from settings;
snapshots are not subscriptions. Query errors should be shown separately from
read/write results. `error` is a string or null. `revision` increases when state
or error changes within one native controller and resets with a new controller.

Controllers on the same Activity share a system registration. Releasing one
leaves the others intact. A request for another Activity returns `failed` while
the registration is held; retry after the previous Activity pauses. Do not
simultaneously register another NFC dispatcher.

iOS queries return `{ platform: 'ios', revision: 0, state: 'unavailable', error: null }`.
Acquisition and release validate the owner ID, then reject with `NFC_UNSUPPORTED`;
the hook therefore skips them on iOS.

## Wait for an Android panel to finish

If navigation or the next action should follow the complete panel animation,
wait for both session idle and panel completion after the original result.
`getPresentationState()` returns `{ platform, supported, activePresentationIds }`.
Android reports all currently shown Sfiora panels in this process, including
closing animations. `waitForPresentationEnd()` captures that set when the call
reaches native code; it resolves with no value when those panels close. Later
panels do not extend it, and an empty set resolves immediately. IDs are temporary;
a headless read adds no panel. Calling before an operation does not wait for a
panel that has yet to appear.

The only option is `timeoutMilliseconds`: integer 1–60000, default 5000.
Invalid options reject with `INVALID_OPTIONS`; the deadline rejects with
`PRESENTATION_TIMEOUT`. A timeout does not close a panel or release the NFC session.
On iOS, the query returns `supported: false` and an empty ID array; waiting rejects
with `NFC_UNSUPPORTED` after validating options. That array does not report the
system sheet's visibility.

This helper delivers the read result immediately and reports each failure under
its own operation name. Its boolean return concerns readiness only, not whether
the read succeeded. The callbacks belong to your screen: preserve the read
result or error and append wait errors separately. Ignore callbacks and readiness
from a screen or operation that is no longer current.

```ts
// Uses the sfiora and Platform imports above.
export async function readAndWaitForUi(
  onResult: (tag: sfiora.NfcTagSnapshot) => void,
  onError: (step: string, error: unknown) => void,
): Promise<boolean> {
  let ready = true;
  const observe = async (step: string, task: Promise<void>) => {
    try {
      await task;
    } catch (error) {
      ready = false;
      onError(step, error);
    }
  };

  try {
    onResult(await sfiora.startScan());
  } catch (error) {
    onError('startScan', error);
  } finally {
    const waits = [observe('waitForIdle', sfiora.waitForIdle())];
    if (Platform.OS === 'android') {
      waits.push(observe('waitForPresentationEnd',
        sfiora.waitForPresentationEnd({ timeoutMilliseconds: 10000 })));
    }
    await Promise.all(waits);
  }
  return ready;
}
```

Keep actions disabled throughout the helper. Only a still-current caller may
use `true` to restore them; continue checking device availability and coordinating
other screens. After `false`, refresh `isScanning()`, `isWriting()`, and Android
`getPresentationState()` before enabling another action. A failed query is not
an idle state. The same observation pattern applies to writes, initialization,
and cancellation, without replacing the original operation result.

Do not start a replacement operation or cancel a completed operation merely to
hide its panel. Replacing an operation on the same controller or tearing down
the host can close the panel immediately, interrupting its normal feedback.

## Options

Common scan options:

| Option | Default | Meaning |
| --- | --- | --- |
| `mode` | `automatic` | `automatic`, `ndef`, or `discover` |
| `timeoutMilliseconds` | `30000` | Integer from `1000` to `60000` |
| `messages` | Built-in messages | Complete `NfcScanMessages` object for customized wording |

Android scan settings go inside the `android` object:

| Option | Default | Meaning |
| --- | --- | --- |
| `presentation` | `managed` | `none` disables the scan panel |
| `deepReadEnabled` | `false` | Optional read-only protocol probes on supported tags |
| `presenceCheckDelayMilliseconds` | `250` | Integer from `50` to `5000` |

For iOS, `ios.pollingTechnologies` defaults to `['iso14443', 'iso15693']`.
It must be a non-empty list; adding `iso18092` also requires FeliCa configuration.
It controls `automatic` and `discover` scans; `ndef` uses the system NDEF reader
instead. Both platform option objects are validated on either OS, but only the
current platform's settings affect scanning.

Write options are `timeoutMilliseconds` with the same range/default and a
complete `NfcWriteMessages` object. They do not accept scan-only options.
Android bridge writes use the managed panel; iOS always uses the system NFC
panel. Unknown scan/write fields and
invalid values are rejected with `INVALID_OPTIONS`; custom `messages` objects
must supply every required non-empty field. See the shipped
[TypeScript declarations](index.d.ts) and `contract/types.ts` for field names.

## Errors and troubleshooting

`SfioraError` exposes `code`, `message`, `recoverable`, and optional
`nativeError`. Branch on `code`; native messages may vary by device and OS.

| Code | Suggested handling |
| --- | --- |
| `NFC_UNSUPPORTED`, `NFC_DISABLED` | Check device support or ask the user to enable NFC |
| `SCAN_BUSY`, `WRITE_BUSY` | Let the current session finish; do not enqueue automatic retries |
| `USER_CANCELLED` | End the local interaction normally |
| `SESSION_CLOSE_TIMEOUT` | Keep actions disabled until a state refresh confirms the session has closed |
| `PRESENTATION_TIMEOUT` | Preserve the result; refresh panel and session state before continuing |
| `SCAN_TIMEOUT`, `WRITE_TIMEOUT`, `TAG_LOST` | Ask the user to retry with stable tag contact |
| `UNSUPPORTED_TAG`, `TAG_READ_ONLY`, `NDEF_CAPACITY_EXCEEDED` | Use a suitable formatted, writable tag or smaller message |
| `READ_FAILED` | Inspect the read error; do not interpret it as an empty tag |
| `WRITE_FAILED`, `WRITE_VERIFICATION_FAILED` | Read again to establish the tag's actual state |
| `INVALID_OPTIONS` | Correct the request before retrying |
| `INTERNAL_ERROR` | Check native linking, app lifecycle, and the native error details |

`recoverable` is a retry hint, not a guarantee that a write left the tag unchanged.
The same write-state uncertainty applies to timeout, cancellation, and tag loss.

For linking errors, rebuild the native app after installation. For iOS session
errors, check the usage description, signed entitlement, and signing profile.

## Privacy and support

Sfiora does not format tags, change passwords, permanently lock tags, clone
access cards, emulate cards, or expose arbitrary APDU/private-block writes.
Tag technologies and read-only details do not imply support for all operations
on that technology.

Tag data is read and processed on the device, and writes use the caller's
contents. Sfiora does not upload tag contents to the author's servers, include
analytics or advertising SDKs, or persist tag contents on the host device.
The host controls application-specific validation, storage, and use of returned data.

When reporting a problem, include the package version, OS/device, operation,
error code, and relevant native error, omitting private tag contents.

[Source and issues](https://github.com/sandroxy/sfiora) ·
[Release history](https://github.com/sandroxy/sfiora/blob/main/CHANGELOG.md) ·
[Apache License 2.0](https://github.com/sandroxy/sfiora/blob/main/LICENSE)
