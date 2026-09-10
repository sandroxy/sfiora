import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../', import.meta.url);
const bridge = await readFile(new URL('adapters/uniapp/bridge.js', root), 'utf8');
const bridgeUrl = 'data:text/javascript;base64,' + Buffer.from(bridge).toString('base64');
let sequence = 0;

async function loadTransport(sourcePath, native) {
  let source = await readFile(new URL(sourcePath, root), 'utf8');
  source = source.replaceAll("'./bridge.js'", JSON.stringify(bridgeUrl));
  source = source.replace(
    "import { invokeSfioraNative } from '@/uni_modules/Sandrox-Sfiora';",
    'const invokeSfioraNative = globalThis.__sfioraTestTransport;'
  );
  globalThis.__sfioraTestTransport = native;
  try {
    return await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64') + `#${++sequence}`);
  } finally {
    delete globalThis.__sfioraTestTransport;
  }
}

test('UTS JS transport preserves all eight methods, arguments and cancellation values', async () => {
  const calls = [];
  const api = await loadTransport('uni_modules/Sandrox-Sfiora/js_sdk/index.js', (method, json, callback) => {
    calls.push([method, JSON.parse(json)]);
    callback(JSON.stringify({ok: true, data: method.startsWith('is') ? true : {method}}));
    callback(JSON.stringify({ok: false, error: {code: 'USER_CANCELLED', message: 'late callback'}}));
  });
  const message = {records: [{kind: 'text', text: 'generic', languageCode: 'en'}]};
  const marker = {domain: 'example.org', type: 'sample'};
  const options = {timeoutMilliseconds: 5000};
  assert.deepEqual(await api.getCapabilities(), {method: 'getCapabilities'});
  assert.deepEqual(await api.startScan(options), {method: 'startScan'});
  assert.equal(await api.isScanning(), true);
  assert.equal(await api.cancelScan(), undefined);
  assert.deepEqual(await api.writeNdef(message, options), {method: 'writeNdef'});
  assert.deepEqual(await api.initializeNdef(message, marker, options), {method: 'initializeNdef'});
  assert.equal(await api.isWriting(), true);
  assert.equal(await api.cancelWrite(), undefined);
  assert.deepEqual(calls, [
    ['getCapabilities', []], ['startScan', [options]], ['isScanning', []], ['cancelScan', []],
    ['writeNdef', [message, options]], ['initializeNdef', [message, marker, options]],
    ['isWriting', []], ['cancelWrite', []],
  ]);
});

test('UTS JS transport rejects malformed JSON and preserves structured NFC errors', async () => {
  const api = await loadTransport('uni_modules/Sandrox-Sfiora/js_sdk/index.js', (_method, _json, callback) => {
    queueMicrotask(() => callback('invalid JSON'));
  });
  await assert.rejects(api.getCapabilities(), {name: 'SfioraError', code: 'INTERNAL_ERROR'});
  const error = {code: 'USER_CANCELLED', message: 'Cancelled after write; tag may have changed', recoverable: true};
  const failed = await loadTransport('uni_modules/Sandrox-Sfiora/js_sdk/index.js', (_method, _json, callback) => {
    queueMicrotask(() => callback(JSON.stringify({ok: false, error})));
  });
  await assert.rejects(failed.writeNdef({records: []}), error);
  await assert.rejects(failed.startScan([]), {code: 'INVALID_OPTIONS'});
});

test('classic wrapper discovers the runtime when called after module loading', async () => {
  const api = await loadTransport('adapters/uniapp/index.js');
  globalThis.uni = {requireNativePlugin: () => ({getCapabilities: callback => callback({ok: true, data: {supported: true}})})};
  try {
    assert.deepEqual(await api.getCapabilities(), {supported: true});
  } finally {
    delete globalThis.uni;
  }
});

test('both UNI products ship the canonical JS bridge unchanged', async () => {
  assert.equal(await readFile(new URL('uni_modules/Sandrox-Sfiora/js_sdk/bridge.js', root), 'utf8'), bridge);
});

test('UTS JS waitForIdle consumes native state without inventing a bridge method', async () => {
  let writingQueries = 0;
  const api = await loadTransport('uni_modules/Sandrox-Sfiora/js_sdk/index.js', (method, _json, callback) => {
    assert.ok(['isScanning', 'isWriting'].includes(method));
    callback(JSON.stringify({ok: true, data: method === 'isWriting' && ++writingQueries < 2}));
  });
  await api.waitForIdle({timeoutMilliseconds: 500});
  assert.equal(writingQueries, 2);
});
