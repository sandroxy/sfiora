import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

import { assertSchemaValue } from '../../contract/schema-fixture-validator.mjs';

const testsDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(testsDirectory, '../..');
const contractFixtures = JSON.parse(
  await readFile(
    resolve(packageRoot, 'tests/fixtures/bridge-contract.json'),
    'utf8'
  )
);
const bridgeSchema = JSON.parse(
  await readFile(resolve(packageRoot, 'contract/bridge.schema.json'), 'utf8')
);
const bridgeSnapshot = contractFixtures.bridgeSnapshot;
const bridgeWriteRequest = contractFixtures.bridgeWriteRequest;
const initializationMarker = bridgeWriteRequest.initializationMarker;
const bridgeWriteResult = {
  schemaVersion: 1,
  platform: 'ios',
  operation: 'writeNdef',
  completedAtEpochMs: 0,
  verified: true,
  bytesWritten: bridgeWriteRequest.expected.byteCount,
  recordCount: bridgeWriteRequest.expected.recordCount,
  messageHex: bridgeWriteRequest.expected.messageHex,
  messageBase64: bridgeWriteRequest.expected.messageBase64,
  tag: bridgeSnapshot,
};
const bridgeInitializationResult = {
  schemaVersion: 1,
  platform: 'ios',
  operation: 'initializeNdef',
  completedAtEpochMs: 0,
  action: 'preserved',
  marker: {
    ...initializationMarker,
    externalType: `${initializationMarker.domain}:${initializationMarker.type}`,
  },
  tag: bridgeSnapshot,
};

test('shared bridge fixtures match the public JSON Schema', () => {
  assertSchemaValue(
    bridgeSnapshot,
    'NfcTagSnapshot',
    'bridgeSnapshot',
    bridgeSchema
  );
  assertSchemaValue(
    bridgeWriteRequest.message,
    'NfcNdefMessageInput',
    'bridgeWriteRequest.message',
    bridgeSchema
  );
  assertSchemaValue(
    bridgeWriteRequest.options,
    'NfcWriteOptions',
    'bridgeWriteRequest.options',
    bridgeSchema
  );
  assertSchemaValue(
    initializationMarker,
    'NfcNdefExternalTypeMarker',
    'bridgeWriteRequest.initializationMarker',
    bridgeSchema
  );
  assertSchemaValue(
    bridgeWriteResult,
    'NfcWriteResult',
    'bridgeWriteResult',
    bridgeSchema
  );
  assertSchemaValue(
    bridgeInitializationResult,
    'NfcNdefInitializationResult',
    'bridgeInitializationResult',
    bridgeSchema
  );
});

async function loadCommonJs(relativePath, requireModule, globals = {}) {
  const absolutePath = resolve(packageRoot, relativePath);
  const source = await readFile(absolutePath, 'utf8');
  const module = { exports: {} };
  const context = vm.createContext({
    Error,
    Promise,
    module,
    exports: module.exports,
    require: requireModule,
    ...globals,
  });
  vm.runInContext(source, context, { filename: absolutePath });
  return module.exports;
}

let esModuleSequence = 0;

async function loadEsModule(relativePath, globals = {}) {
  const absolutePath = resolve(packageRoot, relativePath);
  const source = await readFile(absolutePath, 'utf8');
  esModuleSequence += 1;
  const encodedSource = Buffer.from(source, 'utf8').toString('base64');
  return withGlobalValue(
    'uni',
    Object.prototype.hasOwnProperty.call(globals, 'uni')
      ? globals.uni
      : undefined,
    () =>
      import(
        `data:text/javascript;base64,${encodedSource}#sfiora-${esModuleSequence}`
      )
  );
}

async function withGlobalValue(name, value, operation) {
  const hadValue = Object.prototype.hasOwnProperty.call(globalThis, name);
  const previousValue = globalThis[name];
  if (value === undefined) {
    delete globalThis[name];
  } else {
    globalThis[name] = value;
  }
  try {
    return await operation();
  } finally {
    if (hadValue) {
      globalThis[name] = previousValue;
    } else {
      delete globalThis[name];
    }
  }
}

test('React Native wrapper exposes the frozen methods and forwards options', async () => {
  const scanCalls = [];
  const writeCalls = [];
  const initializeCalls = [];
  const nativeModule = {
    async getCapabilities() {
      return { platform: 'android', supported: true };
    },
    async startScan(options) {
      scanCalls.push(options);
      return bridgeSnapshot;
    },
    async cancelScan() {},
    async isScanning() {
      return true;
    },
    async writeNdef(message, options) {
      writeCalls.push({ message, options });
      return bridgeWriteResult;
    },
    async initializeNdef(message, marker, options) {
      initializeCalls.push({ message, marker, options });
      return bridgeInitializationResult;
    },
    async cancelWrite() {},
    async isWriting() {
      return false;
    },
  };
  const wrapper = await loadCommonJs(
    'adapters/react-native/index.js',
    (name) => {
      assert.equal(name, 'react-native');
      return {
        NativeModules: {},
        TurboModuleRegistry: {
          get(moduleName) {
            assert.equal(moduleName, 'Sfiora');
            return nativeModule;
          },
        },
      };
    }
  );

  assert.deepEqual(
    Object.keys(wrapper).sort(),
    [
      'SfioraError',
      'cancelScan',
      'cancelWrite',
      'getCapabilities',
      'initializeNdef',
      'isScanning',
      'isWriting',
      'startScan',
      'writeNdef',
    ].sort()
  );
  assert.equal((await wrapper.getCapabilities()).supported, true);
  assert.deepEqual(await wrapper.startScan(), bridgeSnapshot);
  assert.equal(scanCalls.length, 1);
  assert.equal(Object.keys(scanCalls[0]).length, 0);
  assert.equal(await wrapper.isScanning(), true);
  await wrapper.cancelScan();
  assert.deepEqual(
    await wrapper.writeNdef(
      bridgeWriteRequest.message,
      bridgeWriteRequest.options
    ),
    bridgeWriteResult
  );
  assert.deepEqual(writeCalls, [
    {
      message: bridgeWriteRequest.message,
      options: bridgeWriteRequest.options,
    },
  ]);
  assert.deepEqual(
    await wrapper.initializeNdef(
      bridgeWriteRequest.message,
      initializationMarker,
      bridgeWriteRequest.options
    ),
    bridgeInitializationResult
  );
  assert.deepEqual(initializeCalls, [
    {
      message: bridgeWriteRequest.message,
      marker: initializationMarker,
      options: bridgeWriteRequest.options,
    },
  ]);
  assert.equal(await wrapper.isWriting(), false);
  await wrapper.cancelWrite();
});

test('React Native wrapper preserves structured native errors', async () => {
  const wrapper = await loadCommonJs(
    'adapters/react-native/index.js',
    () => ({
      NativeModules: {
        Sfiora: {
          async startScan() {
            throw {
              code: 'SCAN_TIMEOUT',
              message: 'Timed out',
              userInfo: {
                code: 'SCAN_TIMEOUT',
                message: 'Timed out',
                recoverable: true,
                nativeError: {
                  type: 'TimeoutException',
                  message: 'Timed out',
                },
              },
            };
          },
        },
      },
      TurboModuleRegistry: {
        get() {
          return null;
        },
      },
    })
  );

  await assert.rejects(wrapper.startScan(), (error) => {
    assert.equal(error.name, 'SfioraError');
    assert.equal(error.code, 'SCAN_TIMEOUT');
    assert.equal(error.recoverable, true);
    assert.equal(error.nativeError.type, 'TimeoutException');
    return true;
  });
});

test('React Native wrapper rejects non-object scan options before bridging', async () => {
  let invocationCount = 0;
  const wrapper = await loadCommonJs(
    'adapters/react-native/index.js',
    () => ({
      NativeModules: {
        Sfiora: {
          async startScan() {
            invocationCount += 1;
          },
        },
      },
      TurboModuleRegistry: null,
    })
  );

  await assert.rejects(wrapper.startScan([]), (error) => {
    assert.equal(error.code, 'INVALID_OPTIONS');
    return true;
  });
  assert.equal(invocationCount, 0);
});

test('React Native wrapper rejects invalid write arguments before bridging', async () => {
  let invocationCount = 0;
  const wrapper = await loadCommonJs(
    'adapters/react-native/index.js',
    () => ({
      NativeModules: {
        Sfiora: {
          async writeNdef() {
            invocationCount += 1;
          },
        },
      },
      TurboModuleRegistry: null,
    })
  );

  await assert.rejects(wrapper.writeNdef(null), (error) => {
    assert.equal(error.code, 'INVALID_OPTIONS');
    return true;
  });
  await assert.rejects(
    wrapper.writeNdef(bridgeWriteRequest.message, []),
    (error) => {
      assert.equal(error.code, 'INVALID_OPTIONS');
      return true;
    }
  );
  await assert.rejects(
    wrapper.initializeNdef(
      bridgeWriteRequest.message,
      null,
      bridgeWriteRequest.options
    ),
    (error) => {
      assert.equal(error.code, 'INVALID_OPTIONS');
      return true;
    }
  );
  assert.equal(invocationCount, 0);
});

test('UniApp wrapper converts callback envelopes to Promise values', async () => {
  const writeCalls = [];
  const initializeCalls = [];
  const nativeModule = {
    getCapabilities(callback) {
      callback({
        ok: true,
        data: { platform: 'ios', supported: true },
      });
    },
    startScan(options, callback) {
      callback({
        ok: true,
        data: {
          ...bridgeSnapshot,
          requestedOptions: options,
        },
      });
    },
    cancelScan(callback) {
      callback({ ok: true, data: {} });
    },
    isScanning(callback) {
      callback({ ok: true, data: false });
    },
    writeNdef(message, options, callback) {
      writeCalls.push({ message, options });
      callback({ ok: true, data: bridgeWriteResult });
    },
    initializeNdef(message, marker, options, callback) {
      initializeCalls.push({ message, marker, options });
      callback({ ok: true, data: bridgeInitializationResult });
    },
    cancelWrite(callback) {
      callback({ ok: true, data: {} });
    },
    isWriting(callback) {
      callback({ ok: true, data: true });
    },
  };
  const wrapper = await loadEsModule(
    'adapters/uniapp/index.js',
    {
      uni: {
        requireNativePlugin(name) {
          assert.equal(name, 'Sfiora');
          return nativeModule;
        },
      },
    }
  );

  assert.deepEqual(
    Object.keys(wrapper).sort(),
    [
      'SfioraError',
      'cancelScan',
      'cancelWrite',
      'getCapabilities',
      'initializeNdef',
      'isScanning',
      'isWriting',
      'startScan',
      'writeNdef',
    ].sort()
  );
  assert.equal((await wrapper.getCapabilities()).platform, 'ios');
  const snapshot = await wrapper.startScan({
    android: { presentation: 'none' },
  });
  assert.equal(snapshot.ndef.records[0].uri, 'https://m.baidu.com');
  assert.equal(snapshot.requestedOptions.android.presentation, 'none');
  assert.equal(await wrapper.isScanning(), false);
  await wrapper.cancelScan();
  assert.deepEqual(
    await wrapper.writeNdef(
      bridgeWriteRequest.message,
      bridgeWriteRequest.options
    ),
    bridgeWriteResult
  );
  assert.deepEqual(writeCalls, [
    {
      message: bridgeWriteRequest.message,
      options: bridgeWriteRequest.options,
    },
  ]);
  assert.deepEqual(
    await wrapper.initializeNdef(
      bridgeWriteRequest.message,
      initializationMarker,
      bridgeWriteRequest.options
    ),
    bridgeInitializationResult
  );
  assert.deepEqual(initializeCalls, [
    {
      message: bridgeWriteRequest.message,
      marker: initializationMarker,
      options: bridgeWriteRequest.options,
    },
  ]);
  assert.equal(await wrapper.isWriting(), true);
  await wrapper.cancelWrite();
});

test('UniApp wrapper rejects native failure envelopes as SfioraError', async () => {
  const wrapper = await loadEsModule(
    'adapters/uniapp/index.js',
    {
      uni: {
        requireNativePlugin() {
          return {
            startScan(_options, callback) {
              callback({
                ok: false,
                error: {
                  code: 'NFC_DISABLED',
                  message: 'NFC is disabled',
                  recoverable: true,
                },
              });
            },
          };
        },
      },
    }
  );

  await assert.rejects(wrapper.startScan(), (error) => {
    assert.equal(error.name, 'SfioraError');
    assert.equal(error.code, 'NFC_DISABLED');
    assert.equal(error.recoverable, true);
    return true;
  });
});

test('UniApp wrapper normalizes missing native module failures', async () => {
  const wrapper = await loadEsModule('adapters/uniapp/index.js');

  await assert.rejects(wrapper.getCapabilities(), (error) => {
    assert.equal(error.name, 'SfioraError');
    assert.equal(error.code, 'INTERNAL_ERROR');
    assert.equal(error.recoverable, false);
    assert.match(error.message, /native module is unavailable/);
    return true;
  });
});

test('UniApp wrapper rejects invalid write arguments before bridging', async () => {
  let invocationCount = 0;
  const wrapper = await loadEsModule(
    'adapters/uniapp/index.js',
    {
      uni: {
        requireNativePlugin() {
          return {
            writeNdef() {
              invocationCount += 1;
            },
          };
        },
      },
    }
  );

  await assert.rejects(wrapper.writeNdef([]), (error) => {
    assert.equal(error.code, 'INVALID_OPTIONS');
    return true;
  });
  await assert.rejects(
    wrapper.writeNdef(bridgeWriteRequest.message, null),
    (error) => {
      assert.equal(error.code, 'INVALID_OPTIONS');
      return true;
    }
  );
  assert.equal(invocationCount, 0);
});
