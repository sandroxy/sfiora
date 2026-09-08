# Sfiora for UniApp

Sfiora provides legacy `nativeplugin` and UTS packages for Android and iOS.
Both expose the same Promise API and structured errors as the React Native
adapter. Install one package per app.

- Legacy UniApp: copy `Sandrox-Sfiora` from the legacy release ZIP into
  `nativeplugins`, then configure the native plugin in `manifest.json`.
- UTS and uni-app x: extract the UTS release ZIP into
  `uni_modules/Sandrox-Sfiora`, with `package.json` directly in that directory.

Build a custom base or application package before testing on a physical device.

```js
import * as sfiora from '@/nativeplugins/Sandrox-Sfiora/js_sdk/index.js';

const capabilities = await sfiora.getCapabilities();
const tag = await sfiora.startScan();
```

For classic UniApp with UTS, use
`@/uni_modules/Sandrox-Sfiora/js_sdk/index.js` as the import path. In uni-app x,
import the methods directly from `@/uni_modules/Sandrox-Sfiora`.

iOS applications must provide `NFCReaderUsageDescription` and enable the
`TAG` NFC reader-session format. Android declares NFC as an
optional device feature and therefore remains installable on devices without
NFC.

Requirements: HBuilderX 5.24 or newer. Classic UniApp requires Android API 21
or iOS 13 or newer; uni-app x requires Android API 23 or iOS 15 or newer.
The UTS marketplace compatibility table uses the common Android API 23 / iOS 15
minimum for both app types; classic UniApp's native configuration remains API 21 / iOS 13.
