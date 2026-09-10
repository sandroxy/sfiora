import { createSfiora } from './bridge.js';
export { SfioraError } from './bridge.js';

const api = createSfiora((method, args, callback) => {
  const runtime = typeof uni === 'undefined' ? undefined : uni;
  const nativeModule = runtime?.requireNativePlugin?.('Sfiora');
  if (!nativeModule || typeof nativeModule[method] !== 'function') {
    throw new Error('Sfiora UniApp native module is unavailable. Install the native plugin and rebuild the app.');
  }
  nativeModule[method](...args, callback);
});

export const {
  waitForIdle, getCapabilities, startScan, cancelScan, isScanning,
  writeNdef, initializeNdef, cancelWrite, isWriting,
} = api;
