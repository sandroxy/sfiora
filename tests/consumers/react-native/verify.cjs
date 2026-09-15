'use strict';

const assert = require('node:assert/strict');

async function verifyInstalledPackage() {
  const sfiora = require('@sandrox/sfiora');
  assert.deepEqual(
    Object.keys(sfiora).sort(),
    [
      'SfioraError',
      'acquireForegroundDispatch', 'releaseForegroundDispatch', 'getForegroundDispatchState',
      'getPresentationState', 'waitForPresentationEnd',
      'cancelScan',
      'cancelWrite',
      'getCapabilities',
      'initializeNdef',
      'isScanning',
      'isWriting',
      'startScan',
      'waitForIdle',
      'writeNdef',
    ].sort()
  );

  await sfiora.waitForIdle();
  assert.equal((await sfiora.getForegroundDispatchState()).state, 'disabled');
  assert.equal((await sfiora.acquireForegroundDispatch('package-consumer')).state, 'active');
  assert.equal((await sfiora.releaseForegroundDispatch('package-consumer')).state, 'disabled');
  assert.equal((await sfiora.getPresentationState()).supported, true);
  assert.equal(await sfiora.waitForPresentationEnd(), undefined);
  const reactNativeCapabilities = await sfiora.getCapabilities();
  assert.equal(reactNativeCapabilities.platform, 'android');
  const writeResult = await sfiora.writeNdef({
    records: [
      {
        kind: 'text',
        text: 'consumer',
        languageCode: 'en',
      },
    ],
  });
  assert.equal(writeResult.operation, 'writeNdef');
}

verifyInstalledPackage().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
