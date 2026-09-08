# Sfiora for React Native

Sfiora exposes NFC capability discovery, tag reading, verified NDEF writing,
and marker-aware NDEF initialization on Android and iOS. It supports React
Native's legacy architecture and TurboModules.

## Install

```sh
npm install @sandrox/sfiora
```

iOS applications must provide `NFCReaderUsageDescription` and the `TAG` NFC
reader-session entitlement. Expo projects can add
`@sandrox/sfiora` to the `plugins` array; the included config plugin applies
the Android NFC declaration and the required iOS settings.

## API

```js
const sfiora = require('@sandrox/sfiora');

const capabilities = await sfiora.getCapabilities();
const tag = await sfiora.startScan();
```

The package exports `getCapabilities`, `startScan`, `cancelScan`,
`isScanning`, `writeNdef`, `initializeNdef`, `cancelWrite`, `isWriting`, and
`SfioraError`. TypeScript declarations include the complete request, result,
and error contract.

Android uses Sfiora's managed NFC panel by default. Pass
`{ android: { presentation: 'none' } }` to run without that panel.

## Requirements

- React Native 0.76 or newer
- Sfiora's native Android minimum is API 21; the application must also meet
  its React Native version's minimum (API 24 for React Native 0.81)
- iOS 13 or newer

Sfiora is licensed under the Apache License 2.0.
