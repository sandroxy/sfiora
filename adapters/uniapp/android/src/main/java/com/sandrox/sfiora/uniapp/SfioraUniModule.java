package com.sandrox.sfiora.uniapp;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;

import com.sandrox.sfiora.NdefExternalType;
import com.sandrox.sfiora.NfcCapabilities;
import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import com.sandrox.sfiora.NfcInitializationResult;
import com.sandrox.sfiora.NfcTagSnapshot;
import com.sandrox.sfiora.NfcWriteResult;
import com.sandrox.sfiora.bridge.SfioraBridgeOptions;
import com.sandrox.sfiora.bridge.SfioraBridgeOptionsException;
import com.sandrox.sfiora.bridge.SfioraBridgeWriteRequest;
import com.sandrox.sfiora.bridge.SfioraBridgeWriteRequestException;
import com.sandrox.sfiora.ui.NfcScanController;
import com.sandrox.sfiora.ui.NfcWriteController;

import java.lang.ref.WeakReference;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import io.dcloud.feature.uniapp.annotation.UniJSMethod;
import io.dcloud.feature.uniapp.bridge.UniJSCallback;
import io.dcloud.feature.uniapp.common.UniModule;

/** Classic UniApp native module for Sfiora's frozen bridge contract. */
public final class SfioraUniModule extends UniModule {
    private NfcScanController scanController;
    private NfcWriteController writeController;
    private WeakReference<Activity> controllerActivityRef =
            new WeakReference<>(null);

    @UniJSMethod(uiThread = true)
    public void getCapabilities(UniJSCallback callback) {
        NfcCapabilities capabilities = NfcCapabilities.from(safeContext());
        invoke(callback, success(capabilities.toMap()));
    }

    @UniJSMethod(uiThread = true)
    public void startScan(Object options, UniJSCallback callback) {
        if (callback == null) {
            return;
        }

        final SfioraBridgeOptions request;
        try {
            request = SfioraBridgeOptions.parse(options);
        } catch (SfioraBridgeOptionsException error) {
            invoke(callback, failure(invalidOptions(error)));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            invoke(callback, failure(hostUnavailable()));
            return;
        }

        ensureControllersFor(activity);
        scanController.startScan(
                request.getReadConfiguration(),
                request.getPresentation(),
                request.getMessages(),
                new NfcClient.ReadCallback() {
                    @Override
                    public void onSuccess(NfcTagSnapshot snapshot) {
                        invoke(callback, success(snapshot.toMap()));
                    }

                    @Override
                    public void onFailure(NfcError error) {
                        invoke(callback, failure(error));
                    }
                }
        );
    }

    @UniJSMethod(uiThread = true)
    public void cancelScan(UniJSCallback callback) {
        if (scanController != null) {
            scanController.cancelScan();
        }
        invoke(callback, success(Collections.emptyMap()));
    }

    @UniJSMethod(uiThread = true)
    public void isScanning(UniJSCallback callback) {
        boolean scanning = scanController != null && scanController.isScanning();
        invoke(callback, success(scanning));
    }

    @UniJSMethod(uiThread = true)
    public void writeNdef(
            Object message,
            Object options,
            UniJSCallback callback
    ) {
        if (callback == null) {
            return;
        }

        final SfioraBridgeWriteRequest request;
        try {
            request = SfioraBridgeWriteRequest.parse(message, options);
        } catch (SfioraBridgeWriteRequestException error) {
            invoke(callback, failure(invalidOptions(error)));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            invoke(callback, failure(hostUnavailable()));
            return;
        }

        ensureControllersFor(activity);
        writeController.startWrite(
                request.getMessage(),
                request.getWriteConfiguration(),
                request.getMessages(),
                new NfcClient.WriteCallback() {
                    @Override
                    public void onSuccess(NfcWriteResult result) {
                        invoke(callback, success(result.toMap()));
                    }

                    @Override
                    public void onFailure(NfcError error) {
                        invoke(callback, failure(error));
                    }
                }
        );
    }

    @UniJSMethod(uiThread = true)
    public void initializeNdef(
            Object message,
            Object marker,
            Object options,
            UniJSCallback callback
    ) {
        if (callback == null) {
            return;
        }

        final SfioraBridgeWriteRequest request;
        final NdefExternalType externalType;
        try {
            request = SfioraBridgeWriteRequest.parse(message, options);
            externalType = SfioraBridgeWriteRequest.parseExternalTypeMarker(marker);
        } catch (SfioraBridgeWriteRequestException error) {
            invoke(callback, failure(invalidOptions(error)));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            invoke(callback, failure(hostUnavailable()));
            return;
        }

        ensureControllersFor(activity);
        try {
            writeController.startInitialize(
                    request.getMessage(),
                    externalType,
                    request.getWriteConfiguration(),
                    request.getMessages(),
                    new NfcClient.InitializationCallback() {
                        @Override
                        public void onSuccess(NfcInitializationResult result) {
                            invoke(callback, success(result.toMap()));
                        }

                        @Override
                        public void onFailure(NfcError error) {
                            invoke(callback, failure(error));
                        }
                    }
            );
        } catch (IllegalArgumentException error) {
            invoke(callback, failure(invalidOptions(error)));
        }
    }

    @UniJSMethod(uiThread = true)
    public void cancelWrite(UniJSCallback callback) {
        if (writeController != null) {
            writeController.cancelWrite();
        }
        invoke(callback, success(Collections.emptyMap()));
    }

    @UniJSMethod(uiThread = true)
    public void isWriting(UniJSCallback callback) {
        boolean writing = writeController != null && writeController.isWriting();
        invoke(callback, success(writing));
    }

    @Override
    public void onActivityPause() {
        releaseControllers(true);
        super.onActivityPause();
    }

    @Override
    public void onActivityDestroy() {
        releaseControllers(true);
        super.onActivityDestroy();
    }

    private Activity availableActivity() {
        Activity activity = safeActivity();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            return null;
        }
        return activity;
    }

    private void ensureControllersFor(Activity activity) {
        Activity controllerActivity = controllerActivityRef.get();
        if (scanController != null
                && writeController != null
                && controllerActivity == activity) {
            return;
        }
        releaseControllers(true);
        scanController = new NfcScanController(activity);
        writeController = new NfcWriteController(activity);
        controllerActivityRef = new WeakReference<>(activity);
    }

    private void releaseControllers(boolean reportCancellation) {
        NfcScanController currentScanController = scanController;
        NfcWriteController currentWriteController = writeController;
        scanController = null;
        writeController = null;
        controllerActivityRef.clear();
        if (currentScanController != null) {
            if (reportCancellation && currentScanController.isScanning()) {
                currentScanController.cancelScan();
            }
            currentScanController.close();
        }
        if (currentWriteController != null) {
            if (reportCancellation && currentWriteController.isWriting()) {
                currentWriteController.cancelWrite();
            }
            currentWriteController.close();
        }
    }

    private Activity safeActivity() {
        Context context = safeContext();
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return context instanceof Activity ? (Activity) context : null;
    }

    private Context safeContext() {
        return mUniSDKInstance == null ? null : mUniSDKInstance.getContext();
    }

    private static NfcError hostUnavailable() {
        return new NfcError(
                NfcErrorCode.INTERNAL_ERROR,
                "The host Activity is not available",
                false
        );
    }

    private static NfcError invalidOptions(Throwable error) {
        String message = error.getMessage() == null
                ? "The NFC options are invalid"
                : error.getMessage();
        return new NfcError(
                NfcErrorCode.INVALID_OPTIONS,
                message,
                true,
                error
        );
    }

    private static void invoke(
            UniJSCallback callback,
            Map<String, Object> envelope
    ) {
        if (callback != null) {
            callback.invoke(envelope);
        }
    }

    private static Map<String, Object> success(Object data) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("ok", true);
        envelope.put("data", data);
        return envelope;
    }

    private static Map<String, Object> failure(NfcError error) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("ok", false);
        envelope.put("error", error.toMap());
        return envelope;
    }
}
