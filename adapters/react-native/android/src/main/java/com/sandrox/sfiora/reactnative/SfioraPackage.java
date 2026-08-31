package com.sandrox.sfiora.reactnative;

import com.facebook.react.BaseReactPackage;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.module.model.ReactModuleInfo;
import com.facebook.react.module.model.ReactModuleInfoProvider;

import java.util.Collections;
import java.util.Map;

public final class SfioraPackage extends BaseReactPackage {
    @Override
    public NativeModule getModule(
            String name,
            ReactApplicationContext reactContext
    ) {
        if (SfioraModule.NAME.equals(name)) {
            return new SfioraModule(reactContext);
        }
        return null;
    }

    @Override
    public ReactModuleInfoProvider getReactModuleInfoProvider() {
        return () -> {
            ReactModuleInfo moduleInfo = new ReactModuleInfo(
                    SfioraModule.NAME,
                    SfioraModule.class.getName(),
                    false,
                    false,
                    false,
                    BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
            );
            Map<String, ReactModuleInfo> modules = Collections.singletonMap(
                    SfioraModule.NAME,
                    moduleInfo
            );
            return modules;
        };
    }
}
