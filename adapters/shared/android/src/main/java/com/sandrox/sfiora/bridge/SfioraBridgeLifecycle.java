package com.sandrox.sfiora.bridge;

import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleEventObserver;
import androidx.lifecycle.LifecycleOwner;

import java.lang.ref.WeakReference;

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

    SfioraBridgeLifecycle(SfioraBridgeRuntime runtime) {
        this.runtime = runtime;
    }

    public static SfioraBridgeLifecycle getShared() {
        return Shared.INSTANCE;
    }

    public void invokeJson(Activity activity, Context applicationContext, String method,
            String arguments, SfioraBridgeJsonCallback callback) {
        Runnable operation = () -> {
            boolean usableHost = bind(activity);
            runtime.invokeJson(usableHost ? activity : applicationContext, method, arguments, callback);
        };
        if (Looper.myLooper() == Looper.getMainLooper()) operation.run();
        else mainHandler.post(operation);
    }

    private boolean bind(Activity activity) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return false;
        if (!(activity instanceof LifecycleOwner)) return false;
        if (activity == activityRef.get()) return true;

        detach();
        runtime.onPause();
        Lifecycle lifecycle = ((LifecycleOwner) activity).getLifecycle();
        if (lifecycle.getCurrentState() == Lifecycle.State.DESTROYED) return false;
        activityRef = new WeakReference<>(activity);
        lifecycleRef = new WeakReference<>(lifecycle);
        // addObserver replays the current state. A background host remains paused;
        // a host recreated before this call receives ON_RESUME immediately.
        lifecycle.addObserver(this);
        return true;
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
        activityRef.clear();
        lifecycleRef.clear();
        if (lifecycle != null) lifecycle.removeObserver(this);
    }
}
