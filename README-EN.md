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
| Classic uni-app UTS | `Sandrox-Sfiora` uni_modules; [guide](adapters/uniapp/README.md) | HBuilderX 5.24, Android API 21 / iOS 13 |
| uni-app x | The same UTS package, Vapor; [guide](adapters/uniapp/README.md) | HBuilderX 5.24, Android API 23 / iOS 15 |

Consult each channel for its published versions. See [CHANGELOG.md](CHANGELOG.md)
for version history and [GitHub Releases](https://github.com/sandroxy/sfiora/releases)
for offline AARs, XCFrameworks, RN packages, and UNI ZIPs. Replace `<version>` in
examples with your selected public version.

## Native Android

Enable Maven Central and add the core and optional UI dependency:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
```

```kotlin
dependencies {
    implementation("io.github.sandroxy:sfiora:<version>")
    implementation("io.github.sandroxy:sfiora-ui:<version>") // optional
}
```

`sfiora` provides headless operations. `sfiora-ui` provides managed panels and
depends on the matching core. RN and UNI packages already include the required
runtimes, so their hosts do not need to add the core separately.

The library manifest declares NFC permission and optional hardware. Check
`client.getCapabilities()` before operations; the application remains
installable on devices without NFC and should display an appropriate message.

This Activity demonstrates the three operations and lifecycle handling. Connect
`readTag`, `replaceTag`, `initializeTag`, and `cancel` to your own buttons; the
example does not define a layout.

```java
import android.app.Activity;
import android.os.Bundle;
import android.widget.Toast;
import com.sandrox.sfiora.*;
import java.util.Collections;

public final class NfcActivity extends Activity {
    private NfcClient client;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        client = new NfcClient(this);
    }

    public void readTag() {
        client.startRead(NfcReadConfiguration.builder().build(),
            new NfcClient.ReadCallback() {
                @Override public void onSuccess(NfcTagSnapshot tag) {
                    show(tag.toPrettyJsonString());
                }
                @Override public void onFailure(NfcError error) {
                    show(error.getCode().getValue() + ": " + error.getMessage());
                }
            });
    }

    public void replaceTag() {
        NdefMessage message = new NdefMessage(Collections.singletonList(
            NdefRecord.text("Hello from Sfiora", "en")));
        client.startWrite(message, NfcWriteConfiguration.builder().build(),
            new NfcClient.WriteCallback() {
                @Override public void onSuccess(NfcWriteResult result) {
                    show("Verified bytes: " + result.getBytesWritten());
                }
                @Override public void onFailure(NfcError error) {
                    show(error.getCode().getValue() + ": " + error.getMessage());
                }
            });
    }

    public void initializeTag() {
        NdefExternalType marker = new NdefExternalType("example.com", "initialized");
        NdefMessage message = new NdefMessage(Collections.singletonList(
            NdefRecord.external(marker.getDomain(), marker.getType(), new byte[]{1, 2, 3})));
        client.startInitialize(message, marker, NfcWriteConfiguration.builder().build(),
            new NfcClient.InitializationCallback() {
                @Override public void onSuccess(NfcInitializationResult result) {
                    show(result.getAction().name());
                }
                @Override public void onFailure(NfcError error) {
                    show(error.getCode().getValue() + ": " + error.getMessage());
                }
            });
    }

    public void cancel() {
        client.cancelRead();
        client.cancelWrite();
    }

    private void show(String text) {
        Toast.makeText(this, text, Toast.LENGTH_LONG).show();
    }

    @Override protected void onPause() {
        client.stop();
        super.onPause();
    }

    @Override protected void onDestroy() {
        client.close();
        super.onDestroy();
    }
}
```

Callbacks run on the main thread. Call `stop()` before the Activity leaves the
foreground, and `close()` when finished with the client. `stop()` is silent and
does not deliver a terminal success/failure callback. For user cancellation,
call `cancelRead()` or `cancelWrite()` and handle the cancellation result.

`NfcReadConfiguration.builder()` defaults to `AUTOMATIC` and a 30-second timeout;
`NDEF` and `DISCOVER` are also available. Read/write timeouts range from 1 to 60
seconds. Start an operation before presenting a tag so the idle system tag
dispatcher does not take over.

For managed Android panels, use
`com.sandrox.sfiora.ui.NfcScanController.startScan(configuration, NfcScanPresentation.MANAGED, callback)`
and `NfcWriteController.startWrite` / `startInitialize`. They use the same callback
types as the core. Create and retain each controller with the foreground
Activity; call `stopScan()` / `stopWrite()` when leaving it and `close()` when
destroying it.

## Native iOS

In Xcode, choose **File > Add Package Dependencies**, then enter:

```text
https://github.com/sandroxy/sfiora.git
```

Select a public version and link the `Sfiora` product to your App target. Swift
Package Manager downloads that version's XCFramework and verifies its checksum.

Add an accurate usage description to your app's `Info.plist`:

```xml
<key>NFCReaderUsageDescription</key>
<string>Read and write NFC tags selected by you.</string>
```

Enable **Near Field Communication Tag Reading** in **Signing & Capabilities**.
The App ID and provisioning profile must include the same capability, and the
signed app must contain this entitlement:

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```

Retain the client as shown below. Call these methods from foreground user
actions. `replaceTag` / `initializeTag` can throw validation errors; use
`do/catch` at the call site. NFC operation results arrive in their completions.

```swift
import UIKit
import Sfiora

final class NfcViewController: UIViewController {
    private let client = NfcClient()

    func readTag() {
        client.startRead { result in
            switch result {
            case .success(let tag):
                print(tag.ndefStatus.rawValue)
                if let message = tag.ndefMessage { print(message.records.count) }
                if let error = tag.ndefReadError { print(error.message) }
            case .failure(let error):
                print(error.code.rawValue, error.message)
            }
        }
    }

    func replaceTag() throws {
        let message = try NdefMessage(records: [
            try NdefRecord.text("Hello from Sfiora", languageCode: "en")
        ])
        client.startWrite(message: message) { result in
            switch result {
            case .success(let value): print(value.bytesWritten)
            case .failure(let error): print(error.code.rawValue, error.message)
            }
        }
    }

    func initializeTag() throws {
        let marker = try NdefExternalType(domain: "example.com", type: "initialized")
        let message = try NdefMessage(records: [
            try NdefRecord.external(
                domain: marker.domain, type: marker.type, payload: Data([1, 2, 3]))
        ])
        try client.startInitialize(message: message, marker: marker) { result in
            switch result {
            case .success(let value): print(value.action.rawValue)
            case .failure(let error): print(error.code.rawValue, error.message)
            }
        }
    }

    func cancel() {
        client.cancelRead()
        client.cancelWrite()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        client.stop()
    }
}
```

Completions and `stateChangeHandler` run on the main thread. Successful results
can arrive before the system panel finishes closing. Use `client.state == .idle`
to decide whether the next action is available. `stop()` silently terminates an
operation when leaving the screen; use `cancelRead()` / `cancelWrite()` for user
cancellation.

The default read configuration is `.automatic`, 30 seconds, polling ISO 14443
and ISO 15693. `.ndef` uses the system NDEF compatibility reader and may omit the
tag identifier. `.discover` does not query NDEF. FeliCa requires opting into
`.iso18092` and providing the applicable system codes; ISO 7816 AIDs are likewise
configured by the host for its supported tags. These discovery settings do not
add arbitrary protocol writes.

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
RN/UNI expose `isScanning()` / `isWriting()` and bounded `waitForIdle()`, and native clients expose their
corresponding states. A cancellation request returning does not mean the panel
has disappeared; still handle the original operation's result.

Branch on stable error codes and keep native errors for diagnosis. `recoverable`
is a retry hint, not a guarantee that a tag was unchanged. Full bridge APIs,
options, and error handling are in the [RN guide](adapters/react-native/README.md)
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

Build and publication procedures are in [RELEASING.md](RELEASING.md). Report
issues with the version, platform, host type, operation, error code, and relevant
native error through [Issues](https://github.com/sandroxy/sfiora/issues), removing
private tag data. Report security issues according to [SECURITY.md](SECURITY.md).

## Privacy and license

Sfiora does not upload tag contents to the author's servers, include analytics
or advertising SDKs, or persist application data for the host. The caller owns
data generation, validation, writing, and any subsequent application storage.

Released under the [Apache License 2.0](LICENSE).
