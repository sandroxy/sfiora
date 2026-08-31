# Sfiora

Sfiora is a contract-first NFC reader and writer for Android, iOS, React
Native, and classic UniApp. Every adapter uses the same native Android and iOS
cores and the same structured bridge contract.

## Capabilities

- Foreground tag discovery and NDEF reading
- Complete NDEF message replacement on formatted, writable tags
- Immediate read-back and byte verification after every successful write
- Marker-based preserve-or-initialize operations using NFC Forum External Types
- Process-wide read/write exclusion, explicit cancellation, and bounded timeouts

Sfiora does not format tags, permanently lock tags, change tag passwords, or
write manufacturer-private memory blocks.

## Packages

| Platform | Distribution | Minimum |
| --- | --- | --- |
| Android | `io.github.sandroxy:sfiora:<version>` and optional `sfiora-ui` | API 21 |
| iOS | Swift Package product `Sfiora` | iOS 13 |
| React Native | `@sandrox/sfiora` | React Native 0.76 |
| Classic UniApp | `Sandrox-Sfiora` nativeplugin ZIP | HBuilderX 5.24 |

### Android

```kotlin
implementation("io.github.sandroxy:sfiora:<version>")
implementation("io.github.sandroxy:sfiora-ui:<version>") // optional managed UI
```

The library manifest contributes the NFC permission and declares NFC hardware
as optional. Create `NfcClient` with the foreground `Activity`, call `stop()`
before that activity leaves the foreground, and call `close()` when the client
is no longer needed. The optional UI artifact adds managed scan and write
panels while keeping NFC behavior in the headless core artifact.

### iOS

Add this repository as a Swift Package dependency and link the `Sfiora`
product. The host application must provide `NFCReaderUsageDescription` and
enable the Near Field Communication Tag Reading capability with both `NDEF`
and `TAG` reader-session formats. FeliCa polling also requires the concrete
system codes used by the host application.

### React Native and UniApp

The adapters expose `getCapabilities`, `startScan`, `cancelScan`, `isScanning`,
`writeNdef`, `initializeNdef`, `cancelWrite`, and `isWriting`, with structured
errors and shared TypeScript definitions.

- [React Native installation and API](adapters/react-native/README.md)
- [Classic UniApp installation and API](adapters/uniapp/README.md)
- [Machine-readable bridge contract](contract/bridge.schema.json)

## Security

Report vulnerabilities according to the [security policy](SECURITY.md).

## License

Sfiora is licensed under the [Apache License 2.0](LICENSE).
