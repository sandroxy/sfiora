'use strict';

const {
  AndroidConfig,
  createRunOncePlugin,
  withAndroidManifest,
  withEntitlementsPlist,
  withInfoPlist,
} = require('@expo/config-plugins');

const packageJson = require('../package.json');

const PLUGIN_NAME = '@sandrox/sfiora';
const DEFAULT_USAGE_DESCRIPTION =
  'Read and write NFC tag data.';

function readHexList(value, label, minimumLength, maximumLength) {
  if (value == null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error(`[${PLUGIN_NAME}] ${label} must be an array.`);
  }
  const result = value.map((item) => {
    if (typeof item !== 'string') {
      throw new Error(
        `[${PLUGIN_NAME}] ${label} must contain hexadecimal strings.`
      );
    }
    return item.trim().toUpperCase();
  });
  const invalidValue = result.some(
    (item) =>
      item.length < minimumLength ||
      item.length > maximumLength ||
      item.length % 2 !== 0 ||
      !/^[0-9A-F]+$/.test(item)
  );
  if (invalidValue) {
    const lengthDescription =
      minimumLength === maximumLength
        ? `${minimumLength}-character`
        : `${minimumLength}-${maximumLength}-character, even-length`;
    throw new Error(
      `[${PLUGIN_NAME}] ${label} must contain ${lengthDescription} hexadecimal strings.`
    );
  }
  return [...new Set(result)];
}

function withSfiora(config, props = {}) {
  if (!props || typeof props !== 'object' || Array.isArray(props)) {
    throw new Error(`[${PLUGIN_NAME}] plugin options must be an object.`);
  }
  const usageDescription =
    typeof props.iosUsageDescription === 'string' &&
    props.iosUsageDescription.trim()
      ? props.iosUsageDescription.trim()
      : DEFAULT_USAGE_DESCRIPTION;
  const iso7816ApplicationIdentifiers = readHexList(
    props.iso7816ApplicationIdentifiers,
    'iso7816ApplicationIdentifiers',
    10,
    32
  );
  const felicaSystemCodes = readHexList(
    props.felicaSystemCodes,
    'felicaSystemCodes',
    4,
    4
  );

  config = withAndroidManifest(config, (androidConfig) => {
    const manifest = androidConfig.modResults.manifest;
    let hasNfcPermission = false;
    manifest['uses-permission'] = (manifest['uses-permission'] || []).filter(
      (permission) => {
        if (permission.$?.['android:name'] !== 'android.permission.NFC') {
          return true;
        }
        if (hasNfcPermission) {
          return false;
        }
        hasNfcPermission = true;
        return true;
      }
    );
    if (!hasNfcPermission) {
      AndroidConfig.Permissions.addPermission(
        androidConfig.modResults,
        'android.permission.NFC'
      );
    }
    const features = Array.isArray(manifest['uses-feature'])
      ? manifest['uses-feature']
      : [];
    if (
      !features.some(
        (feature) =>
          feature.$ &&
          feature.$['android:name'] === 'android.hardware.nfc'
      )
    ) {
      features.push({
        $: {
          'android:name': 'android.hardware.nfc',
          'android:required': 'false',
        },
      });
    }
    manifest['uses-feature'] = features;
    return androidConfig;
  });

  config = withInfoPlist(config, (iosConfig) => {
    iosConfig.modResults.NFCReaderUsageDescription = usageDescription;
    if (iso7816ApplicationIdentifiers.length > 0) {
      iosConfig.modResults[
        'com.apple.developer.nfc.readersession.iso7816.select-identifiers'
      ] = iso7816ApplicationIdentifiers;
    }
    if (felicaSystemCodes.length > 0) {
      iosConfig.modResults[
        'com.apple.developer.nfc.readersession.felica.systemcodes'
      ] = felicaSystemCodes;
    }
    return iosConfig;
  });

  config = withEntitlementsPlist(config, (iosConfig) => {
    iosConfig.modResults[
      'com.apple.developer.nfc.readersession.formats'
    ] = ['TAG'];
    return iosConfig;
  });

  return config;
}

module.exports = createRunOncePlugin(
  withSfiora,
  PLUGIN_NAME,
  packageJson.version
);
