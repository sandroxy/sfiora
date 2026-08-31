# Sfiora for UniApp

This package is a classic DCloud `nativeplugin` for Android and iOS. Its
Promise wrapper exposes the same eight methods and structured errors as the
React Native adapter.

Copy the `Sandrox-Sfiora` directory from the release ZIP into the application's
`nativeplugins` directory, configure the native plugin in `manifest.json`, and
build a custom base or cloud package before testing on a physical device.

```js
import * as sfiora from '@/nativeplugins/Sandrox-Sfiora/js_sdk/index.js';

const capabilities = await sfiora.getCapabilities();
const tag = await sfiora.startScan();
```

iOS applications must provide `NFCReaderUsageDescription` and enable the
`NDEF` and `TAG` NFC reader-session formats. Android declares NFC as an
optional device feature and therefore remains installable on devices without
NFC.

Requirements: HBuilderX 5.24 or newer, Android API 21 or newer, and iOS 13 or
newer.
