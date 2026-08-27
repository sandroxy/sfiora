package com.sandrox.sfiora.ui;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;

import com.sandrox.sfiora.NfcCapabilities;
import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import com.sandrox.sfiora.NfcReadConfiguration;
import com.sandrox.sfiora.NfcTagSnapshot;

import java.lang.ref.WeakReference;
import java.util.Objects;

/**
 * Optional Android presentation facade around the headless {@link NfcClient}.
 *
 * <p>The controller never displays tag content. Managed presentation only
 * communicates scan progress and terminal state; callers receive the same
 * snapshot and error objects as they do when presentation is
 * {@link NfcScanPresentation#NONE}.</p>
 */
public final class NfcScanController implements AutoCloseable {
    private final WeakReference<Activity> activityRef;
    private final NfcClient client;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private ManagedNfcOperationDialog activeDialog;
    private boolean closed;

    public NfcScanController(Activity activity) {
        if (activity == null) {
            throw new IllegalArgumentException("activity is required");
        }
        activityRef = new WeakReference<>(activity);
        client = new NfcClient(activity);
    }

    public NfcCapabilities getCapabilities() {
        return client.getCapabilities();
    }

    public boolean isScanning() {
        return client.isReading();
    }

    public void startScan(
            NfcReadConfiguration configuration,
            NfcScanPresentation presentation,
            NfcClient.ReadCallback callback
    ) {
        startScan(configuration, presentation, null, callback);
    }

    public void startScan(
            NfcReadConfiguration configuration,
            NfcScanPresentation presentation,
            NfcPresentationMessages.Scan messages,
            NfcClient.ReadCallback callback
    ) {
        Objects.requireNonNull(callback, "callback is required");
        runOnMain(() -> startScanOnMain(
                configuration == null
                        ? NfcReadConfiguration.builder().build()
                        : configuration,
                presentation == null
                        ? NfcScanPresentation.MANAGED
                        : presentation,
                messages,
                callback
        ));
    }

    public void cancelScan() {
        client.cancelRead();
    }

    /**
     * Stops scanning and removes managed UI without reporting a user
     * cancellation.
     */
    public void stopScan() {
        runOnMain(() -> {
            dismissDialog();
            client.stop();
        });
    }

    @Override
    public void close() {
        runOnMain(() -> {
            if (closed) {
                return;
            }
            closed = true;
            dismissDialog();
            client.close();
        });
    }

    private void startScanOnMain(
            NfcReadConfiguration configuration,
            NfcScanPresentation presentation,
            NfcPresentationMessages.Scan messages,
            NfcClient.ReadCallback callback
    ) {
        if (closed) {
            callback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "NfcScanController has already been closed",
                    false
            ));
            return;
        }

        if (client.isReading()) {
            callback.onFailure(new NfcError(
                    NfcErrorCode.SCAN_BUSY,
                    "Another NFC reader session is already active",
                    true
            ));
            return;
        }

        dismissDialog();
        if (presentation == NfcScanPresentation.NONE) {
            client.startRead(configuration, callback);
            return;
        }

        Activity activity = activityRef.get();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            callback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "The host Activity is not available",
                    false
            ));
            return;
        }

        ManagedNfcOperationDialog dialog = new ManagedNfcOperationDialog(
                activity,
                ManagedNfcOperationDialog.Operation.READ,
                NfcPresentationMessages.resolveScan(activity, messages),
                client::cancelRead,
                () -> {
                    if (activeDialog != null && !activeDialog.isShowing()) {
                        activeDialog = null;
                    }
                }
        );
        activeDialog = dialog;
        try {
            dialog.showPending();
        } catch (RuntimeException error) {
            activeDialog = null;
            try {
                dialog.dismissWithoutCancellation();
            } catch (RuntimeException ignored) {
                // A broken or detached window has no remaining UI to release.
            }
            callback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "Unable to present the Android NFC scan panel",
                    true,
                    error
            ));
            return;
        }
        if (!dialog.isShowing()) {
            activeDialog = null;
            callback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "The host Activity became unavailable before presentation",
                    true
            ));
            return;
        }
        client.startRead(configuration, new ManagedCallback(dialog, callback));
    }

    private void dismissDialog() {
        ManagedNfcOperationDialog dialog = activeDialog;
        activeDialog = null;
        if (dialog != null) {
            dialog.dismissWithoutCancellation();
        }
    }

    private void runOnMain(Runnable action) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run();
        } else {
            mainHandler.post(action);
        }
    }

    private final class ManagedCallback implements NfcClient.ReadCallback {
        private final ManagedNfcOperationDialog dialog;
        private final NfcClient.ReadCallback callback;

        private ManagedCallback(
                ManagedNfcOperationDialog dialog,
                NfcClient.ReadCallback callback
        ) {
            this.dialog = dialog;
            this.callback = callback;
        }

        @Override
        public void onSuccess(NfcTagSnapshot snapshot) {
            try {
                dialog.showSuccess();
            } finally {
                callback.onSuccess(snapshot);
            }
        }

        @Override
        public void onFailure(NfcError error) {
            try {
                dialog.showError(error);
            } finally {
                callback.onFailure(error);
            }
        }

        @Override
        public void onStateChanged(boolean scanning) {
            callback.onStateChanged(scanning);
        }
    }
}
