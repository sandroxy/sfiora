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
seconds. Start an operation before presenting a tag, or use the optional
foreground dispatcher below if tags may remain nearby between operations.

## Optional foreground tag handling

The optional dispatcher and panel observer require Sfiora 1.2.0 or newer.
By default, Sfiora leaves idle tag dispatch to the system. A screen can opt in
to foreground dispatch while it is visible.
This prevents a nearby tag from opening another tag-handling Activity between
operations. The dispatcher ignores idle tags; scans and writes remain explicit
calls to `NfcClient` or the UI controllers.

`NfcForegroundDispatchController` belongs to the core library and requires no UI
dependency. A host owns the controller and forwards Activity lifecycle events
on the main thread. This example only shows dispatch ownership; merge its
lifecycle calls with your existing read/write cleanup when adding it to an NFC screen.

```java
import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import com.sandrox.sfiora.NfcForegroundDispatchController;
import java.util.Map;

public final class ForegroundNfcActivity extends Activity {
    private NfcForegroundDispatchController foreground;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        foreground = new NfcForegroundDispatchController(this);
        foreground.acquire("nfc-screen");
    }

    @Override protected void onResume() {
        super.onResume();
        foreground.onResume(this);
        Map<String, Object> state = foreground.getState();
        Log.d("NFC", "Foreground dispatch: " + state.get("state"));
        if (state.get("error") != null) Log.w("NFC", state.get("error").toString());
    }

    @Override protected void onPause() {
        foreground.onPause();
        super.onPause();
    }

    @Override protected void onDestroy() {
        foreground.close();
        super.onDestroy();
    }
}
```

The example uses one owner for a controller owned by one Activity. If several
screens share a controller, give each screen lifetime a unique owner ID and
release that ID when it leaves. Acquisition is idempotent. Releasing one ID
leaves other owners intact; releasing an unknown ID is harmless. IDs are 1–128
ASCII characters, start with a letter or digit,
and may otherwise contain letters, digits, `.`, `_`, `:`, or `-`. A controller
can hold at most 128 distinct IDs. Invalid arguments throw `IllegalArgumentException`.

`acquire`, `release`, and `getState` return `{ platform, revision, state, error }`
as a Map. A return value is not proof that dispatch is active: inspect `state`.

| `state` | Meaning |
| --- | --- |
| `disabled` | This controller has no requests |
| `active` | Dispatch is registered on the resumed Activity |
| `paused` | Requests remain, but no usable resumed Activity is available |
| `unavailable` | NFC hardware is unavailable |
| `nfcDisabled` | System NFC is switched off |
| `failed` | Registration or cleanup failed; inspect `error` |

`error` is a diagnostic string or null. `revision` increases when state or error
changes within this controller and resets with a new controller; it is not a
process-wide revision or session ID. Query again when refreshing
screen state, including after returning from NFC settings. Native NFC setting
changes reconcile retained requests without another acquisition.

Requests survive pause/resume; `close()` releases them all and is idempotent.
After closing, acquire/release/query calls are invalid. Dispatch does not occupy
the NFC read/write session or change background tag handling. Do not mix it with
another foreground dispatcher. Controllers on the same Activity share one system
registration; releasing one leaves the others intact. A request for a different
Activity returns `failed` while that registration is held. Retry after the
previous Activity pauses; the failed request does not replace its registration.

The required ordering follows Android's
[foreground-dispatch contract](https://developer.android.com/reference/android/nfc/NfcAdapter#enableForegroundDispatch(android.app.Activity,android.app.PendingIntent,android.content.IntentFilter[],java.lang.String[][])):
enable only for a resumed Activity and disable before `onPause()` returns.

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

### Observe panel completion

A terminal result and `onStateChanged(false)` do not mean the panel has closed.
If the next interaction should follow the full panel animation, observe it with
`NfcPresentationState` as well as the client's read/write state. All presentation
methods run on the main thread.

`NfcPresentationState.getState()` returns an immutable Map containing `platform`,
`supported`, and `activePresentationIds`. The IDs cover all currently displayed
Sfiora panels in the process, including success and dismissal animations.
`waitForEnd` captures that set; an empty set completes immediately, and later
panels never extend the wait. IDs are temporary; do not store them as business
identifiers. A headless operation adds no panel. Calling a wait before starting
an operation does not reserve a wait for its future panel.

This helper uses only the public UI API. Call it from the original operation's
success or failure callback, after preserving or displaying that result. The
logging below reports only completion diagnostics; connect them to a separate
status/error area in your own screen.

```java
import android.util.Log;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.ui.NfcPresentationState;

final class NfcPanelObserver {
    static void afterOperation() {
        NfcPresentationState.waitForEnd(10000, new NfcPresentationState.Completion() {
            @Override public void onSuccess() {
                Log.d("NFC", "Captured panels have closed");
            }

            @Override public void onFailure(NfcError error) {
                Log.w("NFC", "Panel wait: " + error.getCode() + ": " + error.getMessage());
            }
        });
    }
}
```

The timeout argument is required and ranges from 1 to 60000 milliseconds.
An invalid timeout or null completion throws `IllegalArgumentException`.
An expired wait calls `onFailure` with `PRESENTATION_TIMEOUT`; it does not
close a panel or cancel/release an NFC session. Keep the original result and
refresh actual panel and client state after a timeout.

Keep action buttons disabled until both the session and the captured panels
have ended. Only update or navigate from a still-current screen and operation.
Starting another operation on the same controller immediately dismisses the old
panel, including a managed-to-headless read. `stopScan()`, `stopWrite()`, or
controller `close()` also end presentation directly; use them for teardown,
not to wait for the normal animation.

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
| `PRESENTATION_TIMEOUT` | Preserve the result; refresh panel and client state after a UI-panel wait expires |
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
