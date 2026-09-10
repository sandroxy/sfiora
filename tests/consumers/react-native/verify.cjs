'use strict';

const assert = require('node:assert/strict');

async function verifyInstalledPackage() {
  const sfiora = require('@sandrox/sfiora');
  assert.deepEqual(
    Object.keys(sfiora).sort(),
    [
      'SfioraError',
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
