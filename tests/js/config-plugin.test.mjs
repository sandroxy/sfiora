import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const testsDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(testsDirectory, '../..');
const packageJson = JSON.parse(
  await readFile(resolve(packageRoot, 'adapters/react-native/package.json'), 'utf8')
);

async function loadConfigPlugin(state) {
  const pluginPath = resolve(
    packageRoot,
    'adapters/react-native/plugin/withSfiora.js'
  );
  const source = await readFile(pluginPath, 'utf8');
  const module = { exports: {} };
  const applyMod = (config, modResults, action) => {
    action({ modResults });
    return config;
  };
  const configPlugins = {
    AndroidConfig: {
      Permissions: {
        addPermission(androidManifest, permission) {
          state.androidPermissions.push(permission);
          const manifest = androidManifest.manifest;
          manifest['uses-permission'] ||= [];
          manifest['uses-permission'].push({ $: { 'android:name': permission } });
        },
      },
    },
    createRunOncePlugin(plugin, name, version) {
      state.registration = { name, version };
      return plugin;
    },
    withAndroidManifest(config, action) {
      return applyMod(config, state.androidManifest, action);
    },
    withEntitlementsPlist(config, action) {
      return applyMod(config, state.iosEntitlements, action);
    },
    withInfoPlist(config, action) {
      return applyMod(config, state.iosInfoPlist, action);
    },
  };
  const context = vm.createContext({
    module,
    exports: module.exports,
    require(request) {
      if (request === '@expo/config-plugins') {
        return configPlugins;
      }
      if (request === '../package.json') {
        return packageJson;
      }
      throw new Error(`Unexpected config plugin dependency: ${request}`);
    },
  });

  vm.runInContext(source, context, { filename: pluginPath });
  return module.exports;
}

test('Expo config plugin emits current iOS NFC entitlement without changing Android declarations', async () => {
  const state = {
    androidManifest: { manifest: {} },
    androidPermissions: [],
    iosEntitlements: {},
    iosInfoPlist: {},
    registration: null,
  };
  const plugin = await loadConfigPlugin(state);

  plugin(
    {},
    {
      iosUsageDescription: '用于测试 NFC 标签读写。',
    }
  );

  assert.deepEqual(state.registration, {
    name: '@sandrox/sfiora',
    version: packageJson.version,
  });
  assert.deepEqual(state.androidPermissions, ['android.permission.NFC']);

  const nfcFeature = state.androidManifest.manifest['uses-feature'].find(
    (feature) => feature.$['android:name'] === 'android.hardware.nfc'
  );
  assert.ok(nfcFeature);
  assert.equal(nfcFeature.$['android:required'], 'false');
  assert.equal(
    state.iosInfoPlist.NFCReaderUsageDescription,
    '用于测试 NFC 标签读写。'
  );

  const formats =
    state.iosEntitlements[
      'com.apple.developer.nfc.readersession.formats'
    ];
  assert.deepEqual(Array.from(formats), ['TAG']);
  assert.equal(formats.includes('NDEF'), false);
});

test('repeated Expo preparation keeps one NFC permission and removes existing duplicates', async () => {
  const internet = { $: { 'android:name': 'android.permission.INTERNET' } };
  const nfc = { $: { 'android:name': 'android.permission.NFC', 'tools:node': 'merge' } };
  for (const permissions of [[], [internet, nfc, nfc, nfc]]) {
    const state = {
      androidManifest: { manifest: { 'uses-permission': [...permissions] } },
      androidPermissions: [],
      iosEntitlements: {},
      iosInfoPlist: {},
    };
    const plugin = await loadConfigPlugin(state);
    for (let run = 0; run < 3; run += 1) {
      plugin({});
      const manifest = state.androidManifest.manifest;
      const matching = manifest['uses-permission'].filter(
        (permission) => permission.$['android:name'] === 'android.permission.NFC'
      );
      assert.equal(matching.length, 1);
      assert.equal(manifest['uses-feature'].length, 1);
      if (permissions.length > 0) {
        assert.equal(manifest['uses-permission'][0], internet);
        assert.equal(matching[0], nfc);
      }
    }
    assert.equal(state.androidPermissions.length, permissions.length === 0 ? 1 : 0);
  }
});
