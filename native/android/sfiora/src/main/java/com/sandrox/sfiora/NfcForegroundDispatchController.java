package com.sandrox.sfiora;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.nfc.NfcAdapter;
import android.os.Build;
import android.os.Looper;
import java.lang.ref.WeakReference;
import java.util.Collections;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Opt-in foreground dispatch, independent of NFC read/write sessions. Call on
 * main, resume with the visible Activity, and pause before Activity.onPause ends.
 * Owner requests survive pause; close removes this controller's requests only.
 */
public final class NfcForegroundDispatchController implements AutoCloseable {
    private static final Map<Activity, Registration> REGISTRATIONS = new IdentityHashMap<>();
    private final Context context;
    private final Set<String> owners = new HashSet<>();
    private WeakReference<Activity> activity = new WeakReference<>(null);
    private Activity registeredActivity;
    private boolean resumed;
    private boolean listening;
    private boolean closed;
    private long revision;
    private String state = "disabled";
    private String failure;

    private static final class Registration {
        final NfcAdapter adapter;
        final Set<NfcForegroundDispatchController> controllers =
                Collections.newSetFromMap(new IdentityHashMap<>());
        Registration(NfcAdapter adapter) { this.adapter = adapter; }
    }

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context ignored, Intent intent) {
            if (NfcAdapter.ACTION_ADAPTER_STATE_CHANGED.equals(intent.getAction())) {
                reconcile();
            }
        }
    };

    public NfcForegroundDispatchController(Context context) {
        if (context == null) throw new IllegalArgumentException("context is required");
        this.context = Objects.requireNonNull(context.getApplicationContext(), "application context is required");
    }

    public Map<String, Object> acquire(String ownerId) {
        requireOpen();
        validateOwner(ownerId);
        if (!owners.contains(ownerId) && owners.size() >= 128) {
            throw new IllegalArgumentException("At most 128 foreground owners are supported");
        }
        owners.add(ownerId);
        reconcile();
        return getState();
    }

    public Map<String, Object> release(String ownerId) {
        requireOpen();
        validateOwner(ownerId);
        owners.remove(ownerId);
        reconcile();
        return getState();
    }

    public void onResume(Activity host) {
        requireOpen();
        if (host == null) throw new IllegalArgumentException("activity is required");
        activity = new WeakReference<>(host);
        resumed = true;
        reconcile();
    }

    public void onPause() {
        requireMain();
        if (closed) return;
        resumed = false;
        reconcile();
    }

    /** A snapshot, not a promise that NFC is supported or enabled. */
    public Map<String, Object> getState() {
        requireOpen();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("platform", "android");
        result.put("revision", revision);
        result.put("state", state);
        result.put("error", failure);
        return Collections.unmodifiableMap(result);
    }

    @Override public void close() {
        requireMain();
        if (closed) return;
        owners.clear();
        resumed = false;
        reconcile();
        try {
            stopListening();
        } finally {
            activity.clear();
            closed = true;
        }
    }

    private void reconcile() {
        requireMain();
        if (closed) return;
        try {
            if (owners.isEmpty()) {
                try {
                    detach();
                } finally {
                    stopListening();
                }
                publish("disabled", null);
                return;
            }
            NfcAdapter adapter = NfcAdapter.getDefaultAdapter(context);
            if (adapter == null) {
                try {
                    detach();
                } finally {
                    stopListening();
                }
                publish("unavailable", null);
                return;
            }
            if (!listening) {
                IntentFilter filter = new IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED);
                if (Build.VERSION.SDK_INT >= 33) {
                    context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
                } else {
                    context.registerReceiver(receiver, filter);
                }
                listening = true;
            }
            Activity host = activity.get();
            if (!resumed || host == null || host.isFinishing() || host.isDestroyed()) {
                detach();
                publish("paused", null);
                return;
            }
            if (!adapter.isEnabled()) {
                detach();
                publish("nfcDisabled", null);
                return;
            }
            if (registeredActivity != host) {
                detach();
                Registration registration = REGISTRATIONS.get(host);
                if (registration == null) {
                    // Android foreground dispatch is process-wide. In multi-window
                    // hosts, never replace another Activity's still-owned dispatch.
                    if (!REGISTRATIONS.isEmpty()) {
                        publish("failed", "Another Activity still owns Sfiora foreground dispatch; retry after it pauses");
                        return;
                    }
                    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
                    if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE;
                    Intent target = new Intent(context, NfcForegroundReceiver.class)
                            .setAction("com.sandrox.sfiora.FOREGROUND_TAG")
                            .setType("application/vnd.sandrox.sfiora.foreground");
                    PendingIntent intent = PendingIntent.getBroadcast(context, 0x5346494f, target, flags);
                    adapter.enableForegroundDispatch(host, intent, null, null);
                    registration = new Registration(adapter);
                    REGISTRATIONS.put(host, registration);
                }
                registration.controllers.add(this);
                registeredActivity = host;
            }
            publish("active", null);
        } catch (RuntimeException error) {
            publish("failed", error.toString());
        }
    }

    private void detach() {
        Activity host = registeredActivity;
        registeredActivity = null;
        if (host == null) return;
        Registration registration = REGISTRATIONS.get(host);
        if (registration == null) return;
        registration.controllers.remove(this);
        if (registration.controllers.isEmpty()) {
            REGISTRATIONS.remove(host);
            registration.adapter.disableForegroundDispatch(host);
        }
    }

    private void stopListening() {
        if (listening) {
            listening = false;
            context.unregisterReceiver(receiver);
        }
    }

    private void publish(String next, String error) {
        if (!state.equals(next) || !Objects.equals(failure, error)) {
            state = next;
            failure = error;
            revision++;
        }
    }

    public static void validateOwner(String ownerId) {
        if (ownerId == null || !ownerId.matches("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")) {
            throw new IllegalArgumentException("ownerId must be 1-128 ASCII letters, digits, '.', '_', ':' or '-', starting with a letter or digit");
        }
    }

    private void requireOpen() {
        requireMain();
        if (closed) throw new IllegalStateException("The foreground dispatch controller is closed");
    }

    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            throw new IllegalStateException("Foreground dispatch must be accessed on the main thread");
        }
    }
}
