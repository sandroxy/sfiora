package com.sandrox.sfiora.bridge;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Handler;
import android.os.Looper;

import com.sandrox.sfiora.NdefExternalType;
import com.sandrox.sfiora.NfcCapabilities;
import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import com.sandrox.sfiora.NfcInitializationResult;
import com.sandrox.sfiora.NfcTagSnapshot;
import com.sandrox.sfiora.NfcWriteResult;
import com.sandrox.sfiora.ui.NfcScanController;
import com.sandrox.sfiora.ui.NfcWriteController;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** NFC runtime shared by classic UniApp and UTS, independent of DCloud APIs. */
public final class SfioraBridgeRuntime {
    public interface ResultCallback {
        void onResult(Map<String, Object> envelope);
    }

    private static final SfioraBridgeRuntime SHARED = new SfioraBridgeRuntime();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private NfcScanController scanController;
    private NfcWriteController writeController;
    private WeakReference<Activity> controllerActivityRef = new WeakReference<>(null);

    public static SfioraBridgeRuntime getShared() {
        return SHARED;
    }

    public void invokeJson(
            Context context,
            String method,
            String arguments,
            SfioraBridgeJsonCallback callback
    ) {
        if (callback == null) {
            return;
        }
        final Object[] args;
        try {
            JSONArray values = new JSONArray(arguments);
            args = new Object[values.length()];
            for (int index = 0; index < values.length(); index++) {
                args[index] = fromJson(values.get(index));
            }
        } catch (JSONException | IllegalArgumentException error) {
            runOnMain(() -> callback.onResult(new JSONObject(failure(invalidOptions(error))).toString()));
            return;
        }
        invoke(context, method, args,
                envelope -> callback.onResult(new JSONObject(envelope).toString()));
    }

    public void invoke(Context context, String method, Object[] args, ResultCallback callback) {
        if (callback == null) {
            return;
        }
        runOnMain(() -> {
            int count;
            switch (method) {
                case "getCapabilities": case "cancelScan": case "isScanning":
                case "cancelWrite": case "isWriting": count = 0; break;
                case "startScan": count = 1; break;
                case "writeNdef": count = 2; break;
                case "initializeNdef": count = 3; break;
                default:
                    invoke(callback, failure(invalidOptions(new IllegalArgumentException("Unknown NFC method"))));
                    return;
            }
            if (args == null || args.length != count) {
                invoke(callback, failure(invalidOptions(new IllegalArgumentException("Invalid NFC argument count"))));
                return;
            }
            switch (method) {
                case "getCapabilities": getCapabilities(context, callback); break;
                case "startScan": startScan(context, args[0], callback); break;
                case "cancelScan": cancelScan(callback); break;
                case "isScanning": isScanning(callback); break;
                case "writeNdef": writeNdef(context, args[0], args[1], callback); break;
                case "initializeNdef": initializeNdef(context, args[0], args[1], args[2], callback); break;
                case "cancelWrite": cancelWrite(callback); break;
                case "isWriting": isWriting(callback); break;
                default: throw new AssertionError("Unreachable NFC method");
            }
        });
    }

    public void close() {
        runOnMain(() -> releaseControllers(true));
    }

    private void runOnMain(Runnable operation) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            operation.run();
        } else {
            mainHandler.post(operation);
        }
    }

    private static Object fromJson(Object value) throws JSONException {
        if (value == JSONObject.NULL) {
            return null;
        }
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            Map<String, Object> result = new LinkedHashMap<>();
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                result.put(key, fromJson(object.get(key)));
            }
            return result;
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            List<Object> result = new ArrayList<>();
            for (int index = 0; index < array.length(); index++) {
                result.add(fromJson(array.get(index)));
            }
            return result;
        }
        return value;
    }
    public void getCapabilities(Context context, ResultCallback callback) {
        NfcCapabilities capabilities = NfcCapabilities.from(context);
        invoke(callback, success(capabilities.toMap()));
    }

    public void startScan(Context context, Object options, ResultCallback callback) {
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

        Activity activity = availableActivity(context);
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

    public void cancelScan(ResultCallback callback) {
        if (scanController != null) {
            scanController.cancelScan();
        }
        invoke(callback, success(Collections.emptyMap()));
    }

    public void isScanning(ResultCallback callback) {
        boolean scanning = scanController != null && scanController.isScanning();
        invoke(callback, success(scanning));
    }

    public void writeNdef(
            Context context,
            Object message,
            Object options,
            ResultCallback callback
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

        Activity activity = availableActivity(context);
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

    public void initializeNdef(
            Context context,
            Object message,
            Object marker,
            Object options,
            ResultCallback callback
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

        Activity activity = availableActivity(context);
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

    public void cancelWrite(ResultCallback callback) {
        if (writeController != null) {
            writeController.cancelWrite();
        }
        invoke(callback, success(Collections.emptyMap()));
    }

    public void isWriting(ResultCallback callback) {
        boolean writing = writeController != null && writeController.isWriting();
        invoke(callback, success(writing));
    }

    private Activity availableActivity(Context context) {
        Activity activity = safeActivity(context);
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

    private Activity safeActivity(Context context) {
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return context instanceof Activity ? (Activity) context : null;
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
            ResultCallback callback,
            Map<String, Object> envelope
    ) {
        if (callback != null) {
            callback.onResult(envelope);
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
