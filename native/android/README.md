# Sfiora for Android

Foreground NFC discovery, NDEF reads, verified writes, and marker-based
initialization. Requires Android API 21 or newer and a physical NFC-capable
device. The host must also satisfy its framework requirements.

Use the [headless client](#headless-read-write-and-initialization) when the app
owns the NFC interface, or [managed panels](#managed-panels) for the built-in
scan, write, and initialization UI. Both return the same typed results.

## Installation

Enable Maven Central in `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
```

Add the core and optional UI dependency in the app module's `build.gradle.kts`:

```kotlin
dependencies {
    implementation("io.github.sandroxy:sfiora:<version>")
    implementation("io.github.sandroxy:sfiora-ui:<version>") // optional
}
```

Replace `<version>` with the version selected from
[Maven Central](https://central.sonatype.com/artifact/io.github.sandroxy/sfiora).
Keep both dependencies at the same version. `sfiora` provides headless operations.
`sfiora-ui` provides managed panels and
depends on the matching core. RN and UNI packages already include the required
runtimes, so their hosts do not need to add the core separately.

For offline integration, download both matching AARs (or only the core for
headless use) and their SHA-256 sidecars from
[GitHub Releases](https://github.com/sandroxy/sfiora/releases). Add the files to
your app's `libs` directory and declare them with `implementation(files(...))`.
A standalone UI AAR does not resolve its core dependency automatically. Do not
install the same library through both Maven and local AARs.

The library manifest declares NFC permission and optional hardware. Check
`client.getCapabilities()` before operations; the application remains
installable on devices without NFC and should display an appropriate message.

NFC uses a manifest permission, not a runtime permission dialog. The user may
need to enable NFC in system settings.

## Headless read, write, and initialization

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
        if (!canStart()) return;
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
        if (!canStart()) return;
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
        if (!canStart()) return;
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

    private boolean canStart() {
        NfcCapabilities capabilities = client.getCapabilities();
        if (!capabilities.isSupported() || !capabilities.isEnabled()) {
            show("NFC is unavailable or disabled.");
            return false;
        }
        return !client.isReading() && !client.isWriting();
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

## Managed panels

Use one `NfcScanController` and one `NfcWriteController` owned by the foreground
Activity. They report the same typed results and callbacks as the headless
client. A minimal host is shown below; supply callbacks like those above when
connecting these methods to your buttons. Choose this host or the headless host
for a screen, and coordinate actions across screens.

```java
import android.app.Activity;
import android.os.Bundle;
import com.sandrox.sfiora.*;
import com.sandrox.sfiora.ui.*;

public final class ManagedNfcActivity extends Activity {
    private NfcScanController scanner;
    private NfcWriteController writer;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        scanner = new NfcScanController(this);
        writer = new NfcWriteController(this);
    }

    public boolean canStart() {
        NfcCapabilities capabilities = scanner.getCapabilities();
        return capabilities.isSupported() && capabilities.isEnabled()
            && !scanner.isScanning() && !writer.isWriting();
    }

    public void read(NfcClient.ReadCallback callback) {
        if (!canStart()) return;
        scanner.startScan(NfcReadConfiguration.builder().build(),
            NfcScanPresentation.MANAGED, callback);
    }

    public void write(NdefMessage message, NfcClient.WriteCallback callback) {
        if (!canStart()) return;
        writer.startWrite(message, NfcWriteConfiguration.builder().build(), callback);
    }

    public void initialize(NdefMessage message, NdefExternalType marker,
                           NfcClient.InitializationCallback callback) {
        if (!canStart()) return;
        writer.startInitialize(message, marker,
            NfcWriteConfiguration.builder().build(), callback);
    }

    public void cancel() {
        scanner.cancelScan();
        writer.cancelWrite();
    }

    @Override protected void onPause() {
        scanner.stopScan();
        writer.stopWrite();
        super.onPause();
    }

    @Override protected void onDestroy() {
        scanner.close();
        writer.close();
        super.onDestroy();
    }
}
```

`NfcScanPresentation.NONE` disables the scan panel. `NfcWriteController` always
uses its panel; use `NfcClient` for headless writes. Panels show progress and
terminal state, never your tag payload. Success ends the scanning animation,
shows a complete checkmark, and dismisses automatically. Do not call
`stopScan()` / `stopWrite()` from a success callback just to hide the panel:
those lifecycle methods can interrupt its presentation.

To customize wording, use the overload accepting `NfcPresentationMessages.Scan`
or `.Write` immediately before the callback. Supply every non-empty string in
that message object; omitting the object uses built-in Android resources.
Constructor fields are documented in
[NfcPresentationMessages.java](sfiora-ui/src/main/java/com/sandrox/sfiora/ui/NfcPresentationMessages.java).

## Configuration and messages

Read options belong to `NfcReadConfiguration.builder()`; call `build()` after
setting them. Write options belong to `NfcWriteConfiguration.builder()`.
Invalid values throw `IllegalArgumentException` before an NFC operation starts.
Handle construction errors when accepting values from users or remote data.

| Builder method | Default | Meaning |
| --- | --- | --- |
| `mode(...)` | `NfcReadMode.AUTOMATIC` | Read NDEF when available; `NDEF` requires it, `DISCOVER` skips it; read only |
| `timeoutMillis(...)` | `30000` | `1000`–`60000` milliseconds; read and write |
| `presenceCheckDelayMillis(...)` | `250` | `50`–`5000` milliseconds; read and write |
| `deepReadEnabled(...)` | `false` | Additional read-only protocol probes; read only |

Deep reads can report partial memory data for supported Type 2 / Ultralight or
MIFARE Classic tags. Hardware, authentication, tag protection, and connectivity
limit what can be read. Inspect `getReadOnlyProbes()` and its diagnostics;
a successful scan does not guarantee successful probes or a complete memory
dump. Probes issue read/authentication commands, never write, format, lock, or
change keys. They are separate from decoding an NDEF message.

## Reading results and composing records

Prefer typed accessors on `NfcTagSnapshot`. Check `getNdefStatus()` and
`getNdefReadError()` before using `getNdefMessage()`. Tag discovery can succeed
with unreadable or unsupported NDEF; absent metadata is not an empty business
value. `getIdentifier()` can be null; `getTechnologies()`, `getWarnings()`, and
`getPlatformDetails()` describe what this device observed.

The following helper can be added to either Activity:

```java
private void inspectTag(NfcTagSnapshot tag) {
    if (tag.getNdefReadError() != null) {
        android.util.Log.w("NFC", tag.getNdefReadError().toString());
        return;
    }
    NdefMessage message = tag.getNdefMessage();
    if (message == null) return;
    for (NdefRecord record : message.getRecords()) {
        NdefText text = record.getDecodedText();
        if (text != null) android.util.Log.d("NFC", text.getText());
        String uri = record.getDecodedUri();
        if (uri != null) android.util.Log.d("NFC", uri);
        // MIME/external bytes: record.getPayload(); interpret them in your app.
    }
}
```

Log tag contents only in your own development environment. `toMap()` and JSON
helpers preserve bridge metadata and diagnostics but are not needed for normal
native access. A Text record's language code is metadata, not part of its text.

Create messages from these factories, individually or in combination:

```java
NdefMessage message = new NdefMessage(java.util.Arrays.asList(
    NdefRecord.text("Hello", "en"),
    NdefRecord.uri("https://example.com"),
    NdefRecord.mime("application/octet-stream", new byte[]{1, 2, 3}),
    NdefRecord.external("example.com", "initialized", new byte[]{1, 2, 3})
));
```

The message must have at least one record. Native payloads are `byte[]`; the
bridge's Base64 encoding is not used here. `NdefRecord.text` also accepts
`NdefTextEncoding.UTF_16`; the default is UTF-8. Use `getPayload()` for original
record bytes and `message.getSerializedData()` for the full NDEF encoding.

A write replaces the **whole message** and succeeds only after a byte-for-byte
read-back match. `NfcWriteResult.isVerified()` is true on success;
`getBytesWritten()`, `getRecordCount()`, and `getTag()` describe that operation.
The tag must already support NDEF, be writable, and have sufficient capacity.

Initialization requires exactly one external record matching the supplied
marker's lowercase domain/type. An existing match returns
`NfcInitializationAction.PRESERVED`, even if its payload differs: nothing is
written. Otherwise the full message is replaced, including unrelated content,
and the action is `INITIALIZED`. An unreadable existing message is an error.
For a preserved native result, `isVerified()` is false, `getWrittenMessage()` is
null, and write counts are zero; its JSON representation omits write fields.
The marker does not lock a tag, authenticate an identity, or format a blank tag.

## State, cancellation, and errors

Call from the foreground UI thread and retain the client/controllers while
closing. Use `isReading()` / `isWriting()` on a client, or `isScanning()` /
`isWriting()` on the controllers. Disable both actions while a request is
pending or either state is true. Each callback also offers
`onStateChanged(boolean)` for refreshing the host UI; it describes native
activity, not panel-animation completion. State queries cover these instances;
the process-wide coordinator rejects conflicting sessions from other clients.

`cancelRead()` / `cancelWrite()` request cancellation; the original callback
still receives its terminal result. A request returning does not prove native
cleanup has finished. `stop()` is silent, so clear a departing screen's local
pending state yourself. With controllers, `stopScan()` / `stopWrite()` also
remove their panels. Avoid creating replacement clients just to bypass busy.
If cleanup exceeds the five-second grace period, a pending terminal result may
be delivered while native state remains busy; keep checking actual state before
allowing another operation. Native clients do not expose the bridge-only
`waitForIdle()` helper.

Inspect `NfcError.getCode()` (or `getCode().getValue()` for its stable string),
`getMessage()`, `isRecoverable()`, and optional `getCause()`.

| Code | Handling |
| --- | --- |
| `NFC_UNSUPPORTED`, `NFC_DISABLED` | Check hardware or ask the user to enable NFC |
| `SCAN_BUSY`, `WRITE_BUSY` | Wait for the existing session; do not automatically replay a write |
| `USER_CANCELLED` | Finish the current interaction normally |
| `SCAN_TIMEOUT`, `WRITE_TIMEOUT`, `TAG_LOST` | Let the user retry with stable contact |
| `UNSUPPORTED_TAG`, `TAG_READ_ONLY`, `NDEF_CAPACITY_EXCEEDED` | Use a suitable formatted tag or smaller message |
| `READ_FAILED` | Do not interpret unreadable data as empty |
| `WRITE_FAILED`, `WRITE_VERIFICATION_FAILED` | Read again to establish the actual contents |
| `INVALID_OPTIONS`, `INTERNAL_ERROR` | Review inputs, host lifecycle, and the underlying error |

Writes have no rollback: timeout, cancellation, lost contact, or failed
verification can leave changed, partial, or empty content. `recoverable` does
not guarantee the previous contents survived.

Sfiora does not upload tag contents, format or permanently lock tags, change
passwords, clone access cards, emulate cards, or expose arbitrary APDU writes.
Application storage and data interpretation belong to the host.

[Product overview](../../README-EN.md) ·
[Release history](../../CHANGELOG.md) · [Issues](https://github.com/sandroxy/sfiora/issues) ·
[Apache License 2.0](../../LICENSE)
