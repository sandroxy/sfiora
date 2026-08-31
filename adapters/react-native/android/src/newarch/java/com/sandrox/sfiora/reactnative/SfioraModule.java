package com.sandrox.sfiora.reactnative;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.module.annotations.ReactModule;

@ReactModule(name = SfioraModule.NAME)
public final class SfioraModule extends NativeSfioraSpec {
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

    @Override
    public void getCapabilities(Promise promise) {
        delegate.getCapabilities(promise);
    }

    @Override
    public void startScan(ReadableMap options, Promise promise) {
        delegate.startScan(options, promise);
    }

    @Override
    public void cancelScan(Promise promise) {
        delegate.cancelScan(promise);
    }

    @Override
    public void isScanning(Promise promise) {
        delegate.isScanning(promise);
    }

    @Override
    public void writeNdef(
            ReadableMap message,
            ReadableMap options,
            Promise promise
    ) {
        delegate.writeNdef(message, options, promise);
    }

    @Override
    public void initializeNdef(
            ReadableMap message,
            ReadableMap marker,
            ReadableMap options,
            Promise promise
    ) {
        delegate.initializeNdef(message, marker, options, promise);
    }

    @Override
    public void cancelWrite(Promise promise) {
        delegate.cancelWrite(promise);
    }

    @Override
    public void isWriting(Promise promise) {
        delegate.isWriting(promise);
    }

    @Override
    public void invalidate() {
        delegate.invalidate();
        super.invalidate();
    }
}
