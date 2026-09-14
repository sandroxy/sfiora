# Sfiora for iOS

Foreground NFC discovery, NDEF reads, verified writes, and marker-based
initialization using the system NFC panel. Requires iOS 13 or newer and a
physical device with compatible NFC hardware. The host must also satisfy its
framework requirements.

## Installation and signing

In Xcode, choose **File > Add Package Dependencies**, then enter:

```text
https://github.com/sandroxy/sfiora.git
```

Select a public version and link the `Sfiora` product to your App target. Swift
Package Manager downloads that version's XCFramework and verifies its checksum.

For offline integration, download the XCFramework ZIP from
[GitHub Releases](https://github.com/sandroxy/sfiora/releases), verify its SHA-256
against that release's native JSON, and add the extracted framework to your App
target under **Frameworks, Libraries, and Embedded Content**, selecting
**Embed & Sign** for this dynamic framework. Do not also link the same module
through Swift Package Manager.

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

## Read, write, and initialization

Retain the client as shown below. Call these methods from foreground user
actions. `replaceTag` / `initializeTag` can throw validation errors; use
`do/catch` at the call site. NFC operation results arrive in their completions.

```swift
import UIKit
import Sfiora

final class NfcViewController: UIViewController {
    private let client = NfcClient()
    var availabilityDidChange: ((Bool) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        client.stateChangeHandler = { [weak self] _ in
            guard let self else { return }
            self.availabilityDidChange?(self.canStart)
        }
    }

    func readTag() {
        guard canStart else { return }
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
        guard canStart else { return }
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
        guard canStart else { return }
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

    var canStart: Bool {
        client.capabilities.supported && client.capabilities.enabled
            && client.state == .idle
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

Bind `availabilityDidChange` to all of the screen's NFC action buttons and
initialize their state from `canStart`. Completions and `stateChangeHandler`
run on the main thread. Successful results
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

## Configuration and wording

Use `NfcReadConfiguration` or `NfcWriteConfiguration`. Their initializers throw
on invalid timeout or empty wording; `.standard` provides validated defaults.
The read configuration can be passed as `client.startRead(configuration: ...)`;
write and initialization also accept a `configuration:` argument.

| Read configuration | Default | Meaning |
| --- | --- | --- |
| `mode` | `.automatic` | Read NDEF when available; `.ndef` requires it, `.discover` skips it |
| `timeoutMilliseconds` | `30000` | Integer from `1000` to `60000`; also available for writes |
| `pollingTechnologies` | `[.iso14443, .iso15693]` | Non-empty set; `.iso18092` additionally needs FeliCa configuration |
| `alertMessage`, `successMessage`, `multipleTagsMessage` | Built-in English text | Non-empty system-panel text; also available for writes |

For example, use these settings inside `readTag()`:

```swift
let configuration = try NfcReadConfiguration(
    mode: .automatic,
    timeoutMilliseconds: 30_000,
    pollingTechnologies: [.iso14443, .iso15693],
    alertMessage: "Hold your iPhone near the label.",
    successMessage: "Label read.",
    multipleTagsMessage: "Present one label at a time."
)
```

Handle `try` with `do/catch` or make the enclosing method `throws`. For complete
wording customization, use the `presentationMessages:` initializer with
`NfcReaderPresentationMessages` or `NfcWriterPresentationMessages`; supply all
required strings. See the [message models](Sources/Sfiora/NfcPresentationMessages.swift).
The system controls the panel's appearance and dismissal animation.

FeliCa system codes belong in `Info.plist` under
`com.apple.developer.nfc.readersession.felica.systemcodes`. ISO 7816 application
identifiers belong under `com.apple.developer.nfc.readersession.iso7816.select-identifiers`.
Use the real system codes/AIDs for your tags. These settings enable discovery;
they do not add arbitrary protocol commands or Android's deep-read probes.

## Results and record types

Inspect `tag.ndefStatus` and `tag.ndefReadError` before treating
`tag.ndefMessage` as application data. A discovered tag can have unreadable or
unsupported NDEF. `tag.identifier` can be absent; `.ndef` compatibility reads
can lack an identifier even when NDEF was read successfully. Technology names
and optional metadata differ across devices and platforms.

This helper can be added to the view controller:

```swift
func inspectTag(_ tag: NfcTagSnapshot) {
    if let error = tag.ndefReadError {
        print(error.domain, error.code, error.message)
        return
    }
    guard let message = tag.ndefMessage else { return }
    for record in message.records {
        if let text = record.decodedText { print(text.text) }
        if let uri = record.decodedUri { print(uri) }
        // MIME/external bytes: record.payload; interpret them in your app.
    }
}
```

Log tag contents only in your own development environment. A Text record's
language code is metadata, not part of `decodedText.text`. Prefer typed access;
`tag.dictionary` and JSON helpers are available for bridge-shaped diagnostics.

Compose one or more records using native `Data` payloads:

```swift
let message = try NdefMessage(records: [
    try NdefRecord.text("Hello", languageCode: "en"),
    try NdefRecord.uri("https://example.com"),
    try NdefRecord.mime(mediaType: "application/octet-stream", payload: Data([1, 2, 3])),
    try NdefRecord.external(domain: "example.com", type: "initialized", payload: Data([1, 2, 3]))
])
```

Text defaults to UTF-8; the `encoding: .utf16` argument selects UTF-16. The
message must contain at least one record. Use `record.payload` for original
record bytes and `message.serializedData` for the full NDEF encoding.

Writing replaces the **whole NDEF message** on a formatted, writable tag with
enough capacity. Success means `verified == true` after full byte-for-byte
read-back; inspect `bytesWritten`, `recordCount`, and the read-back `tag`.

Initialization requires exactly one external record matching the supplied
marker's lowercase domain/type. Existing matching content returns `.preserved`
without comparing the marker payload or writing anything. Otherwise the entire
message is replaced, including unrelated content, and `.initialized` is
returned after verification. Unreadable existing content is an error.
For a preserved native result, `writtenMessage` is nil, `verified` is false, and
write counts are zero; the dictionary omits write fields. A marker is a
preservation convention, not a lock, identity check, or formatting operation.

## Lifecycle and errors

Keep a client owned by the active screen and start operations on the main
thread from foreground user actions. Use `client.stateChangeHandler` to refresh
buttons when `.reading`, `.writing`, or `.idle` changes; capture the screen
weakly in that handler. Combine native state with any outstanding application
request when deciding whether to allow another action. States describe this
client; another client's active session can still cause a busy error.

Both `cancelRead()` and `cancelWrite()` return before system cleanup is
necessarily complete; handle the original completion too. `stop()` on screen
exit is silent, so clear that screen's own pending state. Invalidate or ignore
late screen updates when navigating away. Do not force the next action through
with a timer or release/recreate the client just to bypass busy.

If system invalidation is delayed beyond five seconds, Sfiora can deliver a
pending result while retaining actual busy state until the OS invalidates the
session. If a recovery retry was waiting for that invalidation, it fails with
`SESSION_CLOSE_TIMEOUT` instead of starting a new session. A successful
completion alone does not enable the next operation. There is no native
`waitForIdle()` API; observe `.idle`. A close timeout does not release the OS
session or justify an automatic retry.

Inspect `NfcError.code`, `message`, `recoverable`, and optional `nativeError`.

| Code | Handling |
| --- | --- |
| `NFC_UNSUPPORTED`, `NFC_DISABLED` | Check physical NFC hardware and capabilities |
| `SCAN_BUSY`, `WRITE_BUSY` | Wait for the active session; do not automatically replay a write |
| `USER_CANCELLED` | Finish the current interaction normally |
| `SESSION_CLOSE_TIMEOUT` | Keep actions disabled until native state actually becomes idle |
| `SCAN_TIMEOUT`, `WRITE_TIMEOUT`, `TAG_LOST` | Let the user retry with stable contact |
| `UNSUPPORTED_TAG`, `TAG_READ_ONLY`, `NDEF_CAPACITY_EXCEEDED` | Use a suitable formatted tag or smaller message |
| `READ_FAILED` | Do not interpret unreadable content as empty |
| `WRITE_FAILED`, `WRITE_VERIFICATION_FAILED` | Read again to establish actual contents |
| `INVALID_OPTIONS`, `INTERNAL_ERROR` | Review inputs, foreground state, signing, and the native error |

For session-start failures, check the actual signed entitlement and provisioning
profile as well as `Info.plist`; editing an unsigned project setting alone is
insufficient. A Simulator build is not an NFC hardware test.

Writes have no rollback. Cancellation, timeout, loss of contact, or failed
verification after writing begins can leave changed, partial, or empty data.
`recoverable` does not guarantee old contents survived. Sfiora does not upload
tag contents, format or permanently lock tags, change passwords, clone access
cards, emulate cards, or expose arbitrary APDU writes. Application storage and
data interpretation belong to the host.

[Product overview](../../README-EN.md) ·
[Release history](../../CHANGELOG.md) · [Issues](https://github.com/sandroxy/sfiora/issues) ·
[Apache License 2.0](../../LICENSE)
