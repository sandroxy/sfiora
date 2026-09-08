package com.sandrox.sfiora.uniapp;

import android.content.Context;
import com.sandrox.sfiora.bridge.SfioraBridgeRuntime;
import io.dcloud.feature.uniapp.annotation.UniJSMethod;
import io.dcloud.feature.uniapp.bridge.UniJSCallback;
import io.dcloud.feature.uniapp.common.UniModule;

/** Classic UniApp transport for the shared NFC runtime. */
public final class SfioraUniModule extends UniModule {
    private final SfioraBridgeRuntime runtime = new SfioraBridgeRuntime();

    @UniJSMethod(uiThread = true)
    public void getCapabilities(UniJSCallback callback) {
        call("getCapabilities", new Object[] {}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void startScan(Object options, UniJSCallback callback) {
        call("startScan", new Object[] {options}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void cancelScan(UniJSCallback callback) {
        call("cancelScan", new Object[] {}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void isScanning(UniJSCallback callback) {
        call("isScanning", new Object[] {}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void writeNdef(Object message, Object options, UniJSCallback callback) {
        call("writeNdef", new Object[] {message, options}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void initializeNdef(Object message, Object marker, Object options, UniJSCallback callback) {
        call("initializeNdef", new Object[] {message, marker, options}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void cancelWrite(UniJSCallback callback) {
        call("cancelWrite", new Object[] {}, callback);
    }

    @UniJSMethod(uiThread = true)
    public void isWriting(UniJSCallback callback) {
        call("isWriting", new Object[] {}, callback);
    }

    private void call(String method, Object[] args, UniJSCallback callback) {
        if (callback == null) {
            return;
        }
        Context context = mUniSDKInstance == null ? null : mUniSDKInstance.getContext();
        runtime.invoke(context, method, args, callback::invoke);
    }

    @Override
    public void onActivityPause() {
        runtime.close();
        super.onActivityPause();
    }

    @Override
    public void onActivityDestroy() {
        runtime.close();
        super.onActivityDestroy();
    }
}
