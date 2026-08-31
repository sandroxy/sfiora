package com.sandrox.sfiora.reactnative;

import android.app.Activity;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;
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

final class SfioraModuleDelegate implements LifecycleEventListener {
    private final ReactApplicationContext reactContext;

    private NfcScanController scanController;
    private NfcWriteController writeController;
    private WeakReference<Activity> controllerActivityRef =
            new WeakReference<>(null);
    private boolean invalidated;

    SfioraModuleDelegate(ReactApplicationContext reactContext) {
        this.reactContext = reactContext;
        reactContext.addLifecycleEventListener(this);
    }

    void getCapabilities(Promise promise) {
        if (invalidated) {
            reject(promise, internalError("The NFC bridge has been invalidated"));
            return;
        }
        NfcCapabilities capabilities = NfcCapabilities.from(reactContext);
        promise.resolve(Arguments.makeNativeMap(capabilities.toMap()));
    }

    void startScan(ReadableMap options, Promise promise) {
        if (invalidated) {
            reject(promise, internalError("The NFC bridge has been invalidated"));
            return;
        }

        final SfioraBridgeOptions bridgeOptions;
        try {
            bridgeOptions = SfioraBridgeOptions.parse(
                    options == null ? null : options.toHashMap()
            );
        } catch (SfioraBridgeOptionsException error) {
            reject(promise, invalidOptions(error));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            reject(promise, internalError("The host Activity is not available"));
            return;
        }

        ensureControllersFor(activity);
        scanController.startScan(
                bridgeOptions.getReadConfiguration(),
                bridgeOptions.getPresentation(),
                bridgeOptions.getMessages(),
                new NfcClient.ReadCallback() {
                    @Override
                    public void onSuccess(NfcTagSnapshot snapshot) {
                        promise.resolve(Arguments.makeNativeMap(snapshot.toMap()));
                    }

                    @Override
                    public void onFailure(NfcError error) {
                        reject(promise, error);
                    }
                }
        );
    }

    void cancelScan(Promise promise) {
        if (scanController != null) {
            scanController.cancelScan();
        }
        promise.resolve(null);
    }

    void isScanning(Promise promise) {
        promise.resolve(scanController != null && scanController.isScanning());
    }

    void writeNdef(
            ReadableMap message,
            ReadableMap options,
            Promise promise
    ) {
        if (invalidated) {
            reject(promise, internalError("The NFC bridge has been invalidated"));
            return;
        }

        final SfioraBridgeWriteRequest request;
        try {
            request = SfioraBridgeWriteRequest.parse(
                    message == null ? null : message.toHashMap(),
                    options == null ? null : options.toHashMap()
            );
        } catch (SfioraBridgeWriteRequestException error) {
            reject(promise, invalidOptions(error));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            reject(promise, internalError("The host Activity is not available"));
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
                        promise.resolve(Arguments.makeNativeMap(result.toMap()));
                    }

                    @Override
                    public void onFailure(NfcError error) {
                        reject(promise, error);
                    }
                }
        );
    }

    void initializeNdef(
            ReadableMap message,
            ReadableMap marker,
            ReadableMap options,
            Promise promise
    ) {
        if (invalidated) {
            reject(promise, internalError("The NFC bridge has been invalidated"));
            return;
        }

        final SfioraBridgeWriteRequest request;
        final NdefExternalType externalType;
        try {
            request = SfioraBridgeWriteRequest.parse(
                    message == null ? null : message.toHashMap(),
                    options == null ? null : options.toHashMap()
            );
            externalType = SfioraBridgeWriteRequest.parseExternalTypeMarker(
                    marker == null ? null : marker.toHashMap()
            );
        } catch (SfioraBridgeWriteRequestException error) {
            reject(promise, invalidOptions(error));
            return;
        }

        Activity activity = availableActivity();
        if (activity == null) {
            reject(promise, internalError("The host Activity is not available"));
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
                            promise.resolve(
                                    Arguments.makeNativeMap(result.toMap())
                            );
                        }

                        @Override
                        public void onFailure(NfcError error) {
                            reject(promise, error);
                        }
                    }
            );
        } catch (IllegalArgumentException error) {
            reject(promise, invalidOptions(error));
        }
    }

    void cancelWrite(Promise promise) {
        if (writeController != null) {
            writeController.cancelWrite();
        }
        promise.resolve(null);
    }

    void isWriting(Promise promise) {
        promise.resolve(writeController != null && writeController.isWriting());
    }

    void invalidate() {
        if (invalidated) {
            return;
        }
        invalidated = true;
        reactContext.removeLifecycleEventListener(this);
        releaseControllers(true);
    }

    @Override
    public void onHostResume() {
        // Operations start only in direct response to a bridge call.
    }

    @Override
    public void onHostPause() {
        releaseControllers(true);
    }

    @Override
    public void onHostDestroy() {
        releaseControllers(true);
    }

    private Activity availableActivity() {
        Activity activity = reactContext.getCurrentActivity();
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

    private static NfcError internalError(String message) {
        return new NfcError(NfcErrorCode.INTERNAL_ERROR, message, false);
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

    private static void reject(Promise promise, NfcError error) {
        promise.reject(
                error.getCode().getValue(),
                error.getMessage(),
                error.getCause(),
                Arguments.makeNativeMap(error.toMap())
        );
    }
}
