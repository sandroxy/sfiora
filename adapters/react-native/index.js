'use strict';

const { NativeModules, TurboModuleRegistry } = require('react-native');

const LINKING_ERROR =
  '@sandrox/sfiora is not linked. Rebuild the native app after installing the package.';

function getNativeModule() {
  const turboModule =
    TurboModuleRegistry && typeof TurboModuleRegistry.get === 'function'
      ? TurboModuleRegistry.get('Sfiora')
      : null;
  const nativeModule = turboModule || NativeModules.Sfiora;
  if (!nativeModule) {
    throw new Error(LINKING_ERROR);
  }
  return nativeModule;
}

class SfioraError extends Error {
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

function normalizeNativeError(error) {
  if (error instanceof SfioraError) {
    return error;
  }
  const userInfo =
    error && error.userInfo && typeof error.userInfo === 'object'
      ? error.userInfo
      : {};
  return new SfioraError(
    {
      ...userInfo,
      code:
        userInfo.code ||
        (error && typeof error.code === 'string'
          ? error.code
          : 'INTERNAL_ERROR'),
      message:
        userInfo.message ||
        (error && typeof error.message === 'string'
          ? error.message
          : 'The NFC operation failed'),
      recoverable:
        typeof userInfo.recoverable === 'boolean'
          ? userInfo.recoverable
          : false,
    },
    error
  );
}

async function invoke(method, ...args) {
  try {
    return await getNativeModule()[method](...args);
  } catch (error) {
    throw normalizeNativeError(error);
  }
}

function getCapabilities() {
  return invoke('getCapabilities');
}

function startScan(options = {}) {
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

function cancelScan() {
  return invoke('cancelScan');
}

function isScanning() {
  return invoke('isScanning');
}

function writeNdef(message, options = {}) {
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

function initializeNdef(message, marker, options = {}) {
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

function cancelWrite() {
  return invoke('cancelWrite');
}

function isWriting() {
  return invoke('isWriting');
}

module.exports = {
  SfioraError,
  cancelScan,
  cancelWrite,
  getCapabilities,
  isScanning,
  isWriting,
  initializeNdef,
  startScan,
  writeNdef,
};
