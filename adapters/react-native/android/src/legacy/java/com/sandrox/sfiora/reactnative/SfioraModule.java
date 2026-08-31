package com.sandrox.sfiora.reactnative;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.module.annotations.ReactModule;

@ReactModule(name = SfioraModule.NAME)
public final class SfioraModule extends ReactContextBaseJavaModule {
    static final String NAME = "Sfiora";

    private final SfioraModuleDelegate delegate;

    public SfioraModule(ReactApplicationContext reactContext) {
        super(reactContext);
        delegate = new SfioraModuleDelegate(reactContext);
    }

    @Override
    public String getName() {
        return NAME;
    }

    @ReactMethod
    public void getCapabilities(Promise promise) {
        delegate.getCapabilities(promise);
    }

    @ReactMethod
    public void startScan(ReadableMap options, Promise promise) {
        delegate.startScan(options, promise);
    }

    @ReactMethod
    public void cancelScan(Promise promise) {
        delegate.cancelScan(promise);
    }

    @ReactMethod
    public void isScanning(Promise promise) {
        delegate.isScanning(promise);
    }

    @ReactMethod
    public void writeNdef(
            ReadableMap message,
            ReadableMap options,
            Promise promise
    ) {
        delegate.writeNdef(message, options, promise);
    }

    @ReactMethod
    public void initializeNdef(
            ReadableMap message,
            ReadableMap marker,
            ReadableMap options,
            Promise promise
    ) {
        delegate.initializeNdef(message, marker, options, promise);
    }

    @ReactMethod
    public void cancelWrite(Promise promise) {
        delegate.cancelWrite(promise);
    }

    @ReactMethod
    public void isWriting(Promise promise) {
        delegate.isWriting(promise);
    }

    @Override
    public void invalidate() {
        delegate.invalidate();
        super.invalidate();
    }
}
