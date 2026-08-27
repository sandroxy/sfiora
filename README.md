# Sfiora

Sfiora is a contract-first NFC reader and writer for Android, iOS, React Native,
and UniApp.

Sfiora has not published a stable release yet.

The repository currently contains the native Android and iOS implementation.
React Native and UniApp adapters have not been published.

## Native capabilities

- Foreground tag discovery and NDEF reading
- Complete NDEF message replacement on already formatted, writable tags
- Immediate read-back and byte verification after every successful write
- Marker-based preserve-or-initialize operations using NFC Forum External Types
- Process-wide read/write exclusion, explicit cancellation, and bounded timeouts

Sfiora does not format tags, permanently lock tags, change tag passwords, or
write manufacturer-private memory blocks.

Android requires API 21 or newer. The library manifest contributes the NFC
permission and declares NFC hardware as optional. Create `NfcClient` with the
foreground `Activity`, call `stop()` before that activity leaves the foreground,
and call `close()` when the client is no longer needed. The optional `sfiora-ui`
module adds a managed scan and write panel while keeping NFC behavior in the
headless `sfiora` module.

iOS requires iOS 13 or newer. The host app must provide
`NFCReaderUsageDescription` and enable the Near Field Communication Tag Reading
capability with both `NDEF` and `TAG` reader-session formats. FeliCa polling also
requires the host app to declare the concrete system codes it uses.

## Security

Report vulnerabilities according to the [security policy](SECURITY.md).

## License

Sfiora is licensed under the [Apache License 2.0](LICENSE).
