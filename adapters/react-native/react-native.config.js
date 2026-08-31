'use strict';

module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath:
          'import com.sandrox.sfiora.reactnative.SfioraPackage;',
        packageInstance: 'new SfioraPackage()',
      },
      ios: {
        podspecPath: './SfioraReactNative.podspec',
      },
    },
  },
};
