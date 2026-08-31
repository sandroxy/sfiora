'use strict';

const nativeModule = {
  async getCapabilities() {
    return {
      platform: 'android',
      supported: true,
      enabled: true,
      readerModeSupported: true,
      features: [],
    };
  },
  async startScan() {
    return {
      schemaVersion: 1,
      platform: 'android',
    };
  },
  async cancelScan() {},
  async isScanning() {
    return false;
  },
  async writeNdef() {
    return {
      schemaVersion: 1,
      platform: 'android',
      operation: 'writeNdef',
      verified: true,
    };
  },
  async initializeNdef() {
    return {
      schemaVersion: 1,
      platform: 'android',
      operation: 'initializeNdef',
      action: 'preserved',
    };
  },
  async cancelWrite() {},
  async isWriting() {
    return false;
  },
};

module.exports = {
  NativeModules: {
    Sfiora: nativeModule,
  },
  TurboModuleRegistry: {
    get(name) {
      return name === 'Sfiora' ? nativeModule : null;
    },
  },
};
