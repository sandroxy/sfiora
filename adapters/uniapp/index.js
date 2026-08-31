const MODULE_NAME = 'Sfiora';
const LINKING_ERROR =
  'Sfiora UniApp native module is unavailable. Install the native plugin and rebuild the app.';
const UNI_RUNTIME = typeof uni === 'undefined' ? undefined : uni;

export class SfioraError extends Error {
  constructor(payload, cause) {
    const safePayload = payload && typeof payload === 'object' ? payload : {};
    super(
      typeof safePayload.message === 'string'
        ? safePayload.message
        : 'The NFC operation failed'
    );
    this.name = 'SfioraError';
    this.code =
      typeof safePayload.code === 'string'
        ? safePayload.code
        : 'INTERNAL_ERROR';
    this.recoverable = Boolean(safePayload.recoverable);
    this.nativeError =
      safePayload.nativeError && typeof safePayload.nativeError === 'object'
        ? safePayload.nativeError
        : undefined;
    this.cause = cause;
  }
}

function normalizeBridgeError(error) {
  if (error instanceof SfioraError) {
    return error;
  }
  const payload = error && typeof error === 'object' ? error : {};
  return new SfioraError(
    {
      code:
        typeof payload.code === 'string'
          ? payload.code
          : 'INTERNAL_ERROR',
      message:
        typeof payload.message === 'string'
          ? payload.message
          : 'The native NFC bridge call failed',
      recoverable:
        typeof payload.recoverable === 'boolean'
          ? payload.recoverable
          : false,
      nativeError:
        payload.nativeError && typeof payload.nativeError === 'object'
          ? payload.nativeError
          : undefined,
    },
    error
  );
}

function getNativeModule() {
  if (
    !UNI_RUNTIME ||
    typeof UNI_RUNTIME.requireNativePlugin !== 'function'
  ) {
    throw new Error(LINKING_ERROR);
  }
  const nativeModule = UNI_RUNTIME.requireNativePlugin(MODULE_NAME);
  if (!nativeModule) {
    throw new Error(LINKING_ERROR);
  }
  return nativeModule;
}

function invoke(method, ...args) {
  return new Promise((resolve, reject) => {
    let nativeModule;
    try {
      nativeModule = getNativeModule();
    } catch (error) {
      reject(normalizeBridgeError(error));
      return;
    }

    const callback = (envelope) => {
      if (envelope && envelope.ok === true) {
        resolve(envelope.data);
        return;
      }
      const payload =
        envelope && envelope.error && typeof envelope.error === 'object'
          ? envelope.error
          : {
              code: 'INTERNAL_ERROR',
              message: 'The native NFC bridge returned an invalid response',
              recoverable: false,
            };
      reject(new SfioraError(payload, envelope));
    };

    try {
      nativeModule[method](...args, callback);
    } catch (error) {
      reject(normalizeBridgeError(error));
    }
  });
}

export function getCapabilities() {
  return invoke('getCapabilities');
}

export function startScan(options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'startScan options must be an object',
        recoverable: true,
      })
    );
  }
  return invoke('startScan', options);
}

export async function cancelScan() {
  await invoke('cancelScan');
}

export function isScanning() {
  return invoke('isScanning');
}

export function writeNdef(message, options = {}) {
  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'writeNdef message must be an object',
        recoverable: true,
      })
    );
  }
  if (!options || typeof options !== 'object' || Array.isArray(options)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'writeNdef options must be an object',
        recoverable: true,
      })
    );
  }
  return invoke('writeNdef', message, options);
}

export function initializeNdef(message, marker, options = {}) {
  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'initializeNdef message must be an object',
        recoverable: true,
      })
    );
  }
  if (!marker || typeof marker !== 'object' || Array.isArray(marker)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'initializeNdef marker must be an object',
        recoverable: true,
      })
    );
  }
  if (!options || typeof options !== 'object' || Array.isArray(options)) {
    return Promise.reject(
      new SfioraError({
        code: 'INVALID_OPTIONS',
        message: 'initializeNdef options must be an object',
        recoverable: true,
      })
    );
  }
  return invoke('initializeNdef', message, marker, options);
}

export async function cancelWrite() {
  await invoke('cancelWrite');
}

export function isWriting() {
  return invoke('isWriting');
}
