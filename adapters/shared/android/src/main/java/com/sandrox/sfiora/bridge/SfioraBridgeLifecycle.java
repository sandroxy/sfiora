package com.sandrox.sfiora.bridge;

import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleEventObserver;
import androidx.lifecycle.LifecycleOwner;

import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;

import java.lang.ref.WeakReference;
import java.util.LinkedHashMap;
import java.util.Map;

import org.json.JSONObject;

/** Binds UTS calls to the actual host Activity, including an already-resumed replacement. */
public final class SfioraBridgeLifecycle implements LifecycleEventObserver {
    private static final class Shared {
        private static final SfioraBridgeLifecycle INSTANCE =
                new SfioraBridgeLifecycle(SfioraBridgeRuntime.getShared());
    }

    private final SfioraBridgeRuntime runtime;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private WeakReference<Activity> activityRef = new WeakReference<>(null);
    private WeakReference<Lifecycle> lifecycleRef = new WeakReference<>(null);
    private volatile long bindingGeneration;
    private boolean bindingInProgress;

    SfioraBridgeLifecycle(SfioraBridgeRuntime runtime) {
        this.runtime = runtime;
    }

    public static SfioraBridgeLifecycle getShared() {
        return Shared.INSTANCE;
    }

    public void invokeJson(Activity activity, Context applicationContext, String method,
            String arguments, SfioraBridgeJsonCallback callback) {
        if (callback == null) return;
        long requestedGeneration = bindingGeneration;
        Runnable operation = () -> {
            // A queued call may query the shared state, but cannot select an older host.
            boolean currentRequest = requestedGeneration == bindingGeneration || activity == activityRef.get();
            boolean usableHost = currentRequest && bind(activity);
            if (!usableHost && activity != null && ("acquireForegroundDispatch".equals(method)
                    || "cancelScan".equals(method) || "cancelWrite".equals(method))) {
                rejectUnavailableHost(callback);
                return;
            }
            if (startsOperation(method)) {
                Lifecycle lifecycle = lifecycleRef.get();
                usableHost = usableHost && !bindingInProgress && lifecycle != null
                        && lifecycle.getCurrentState() == Lifecycle.State.RESUMED;
            }
            // Keep background queries, cancellation and owner release available. Only
            // operation starts need a resumed Activity; the runtime validates their
            // arguments and reports its existing unavailable-host error otherwise.
            Context fallback = applicationContext == null ? null : applicationContext.getApplicationContext();
            runtime.invokeJson(usableHost ? activity : fallback, method, arguments, callback);
        };
        if (Looper.myLooper() == Looper.getMainLooper()) operation.run();
        else mainHandler.post(operation);
    }

    private boolean bind(Activity activity) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return false;
        if (!(activity instanceof LifecycleOwner)) return false;
        if (activity == activityRef.get()) return true;
        Lifecycle lifecycle = ((LifecycleOwner) activity).getLifecycle();
        if (lifecycle.getCurrentState() == Lifecycle.State.DESTROYED) return false;
        Lifecycle currentLifecycle = lifecycleRef.get();
        if (activityRef.get() != null && (lifecycle.getCurrentState() != Lifecycle.State.RESUMED
                || (currentLifecycle != null && currentLifecycle.getCurrentState() == Lifecycle.State.RESUMED))) {
            return false;
        }

        detach();
        activityRef = new WeakReference<>(activity);
        lifecycleRef = new WeakReference<>(lifecycle);
        bindingInProgress = true;
        try {
            // Publish the new owner before cancelling old operations: their callbacks
            // may reenter the bridge and must not bind the previous Activity again.
            runtime.onPause();
            // addObserver replays the current state. A background host stays paused;
            // an already-resumed replacement receives ON_RESUME immediately.
            lifecycle.addObserver(this);
        } finally {
            bindingInProgress = false;
        }
        return true;
    }

    private static boolean startsOperation(String method) {
        return "startScan".equals(method) || "writeNdef".equals(method) || "initializeNdef".equals(method);
    }

    private static void rejectUnavailableHost(SfioraBridgeJsonCallback callback) {
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("ok", false);
        envelope.put("error", new NfcError(NfcErrorCode.INTERNAL_ERROR,
                "The host Activity is not available", false).toMap());
        callback.onResult(new JSONObject(envelope).toString());
    }

    @Override public void onStateChanged(LifecycleOwner source, Lifecycle.Event event) {
        Activity activity = activityRef.get();
        if (source != activity) return;
        if (event == Lifecycle.Event.ON_RESUME) {
            runtime.onResume(activity);
        } else if (event == Lifecycle.Event.ON_PAUSE) {
            runtime.onPause();
        } else if (event == Lifecycle.Event.ON_DESTROY) {
            detach();
            runtime.close();
        }
    }

    private void detach() {
        Lifecycle lifecycle = lifecycleRef.get();
        bindingGeneration++;
        activityRef.clear();
        lifecycleRef.clear();
        if (lifecycle != null) lifecycle.removeObserver(this);
    }
}
