package com.sandrox.sfiora.ui;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;

import com.sandrox.sfiora.NdefExternalType;
import com.sandrox.sfiora.NdefMessage;
import com.sandrox.sfiora.NdefRecord;
import com.sandrox.sfiora.NfcCapabilities;
import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import com.sandrox.sfiora.NfcInitializationResult;
import com.sandrox.sfiora.NfcWriteConfiguration;
import com.sandrox.sfiora.NfcWriteResult;

import java.lang.ref.WeakReference;
import java.util.Objects;

/**
 * Optional managed Android presentation facade around the headless
 * {@link NfcClient}.
 *
 * <p>The panel only communicates write progress and terminal state. It never
 * displays or transforms the NDEF payload, and callers receive the same result
 * and error objects as when they use {@link NfcClient} directly.</p>
 */
public final class NfcWriteController implements AutoCloseable {
    private final WeakReference<Activity> activityRef;
    private final NfcClient client;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private ManagedNfcOperationDialog activeDialog;
    private boolean closed;

    public NfcWriteController(Activity activity) {
        if (activity == null) {
            throw new IllegalArgumentException("activity is required");
        }
        activityRef = new WeakReference<>(activity);
        client = new NfcClient(activity);
    }

    public NfcCapabilities getCapabilities() {
        return client.getCapabilities();
    }

    public boolean isWriting() {
        return client.isWriting();
    }

    public void startWrite(
            NdefMessage message,
            NfcWriteConfiguration configuration,
            NfcClient.WriteCallback callback
    ) {
        startWrite(message, configuration, null, callback);
    }

    public void startInitialize(
            NdefMessage message,
            NdefExternalType marker,
            NfcWriteConfiguration configuration,
            NfcClient.InitializationCallback callback
    ) {
        startInitialize(message, marker, configuration, null, callback);
    }

    public void startInitialize(
            NdefMessage message,
            NdefExternalType marker,
            NfcWriteConfiguration configuration,
            NfcPresentationMessages.Write messages,
            NfcClient.InitializationCallback callback
    ) {
        Objects.requireNonNull(message, "message is required");
        Objects.requireNonNull(marker, "marker is required");
        Objects.requireNonNull(callback, "callback is required");
        int matchingRecordCount = 0;
        for (NdefRecord record : message.getRecords()) {
            if (marker.matches(record)) {
                matchingRecordCount += 1;
            }
        }
        if (matchingRecordCount != 1) {
            throw new IllegalArgumentException(
                    "message must contain exactly one record matching marker"
            );
        }
        runOnMain(() -> startInitializeOnMain(
                message,
                marker,
                configuration == null
                        ? NfcWriteConfiguration.builder().build()
                        : configuration,
                messages,
                callback
        ));
    }

    public void startWrite(
            NdefMessage message,
            NfcWriteConfiguration configuration,
            NfcPresentationMessages.Write messages,
            NfcClient.WriteCallback callback
    ) {
        Objects.requireNonNull(message, "message is required");
        Objects.requireNonNull(callback, "callback is required");
        runOnMain(() -> startWriteOnMain(
                message,
                configuration == null
                        ? NfcWriteConfiguration.builder().build()
                        : configuration,
                messages,
                callback
        ));
    }

    public void startWrite(
            NdefMessage message,
            NfcClient.WriteCallback callback
    ) {
        startWrite(
                message,
                NfcWriteConfiguration.builder().build(),
                callback
        );
    }

    public void startInitialize(
            NdefMessage message,
            NdefExternalType marker,
            NfcClient.InitializationCallback callback
    ) {
        startInitialize(
                message,
                marker,
                NfcWriteConfiguration.builder().build(),
                callback
        );
    }

    public void cancelWrite() {
        client.cancelWrite();
    }

    /**
     * Stops writing and removes managed UI without reporting a user
     * cancellation.
     */
    public void stopWrite() {
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

    private void startWriteOnMain(
            NdefMessage message,
            NfcWriteConfiguration configuration,
            NfcPresentationMessages.Write messages,
            NfcClient.WriteCallback callback
    ) {
        ManagedNfcOperationDialog dialog = prepareDialog(messages, callback);
        if (dialog == null) {
            return;
        }
        client.startWrite(
                message,
                configuration,
                new ManagedCallback(dialog, callback)
        );
    }

    private void startInitializeOnMain(
            NdefMessage message,
            NdefExternalType marker,
            NfcWriteConfiguration configuration,
            NfcPresentationMessages.Write messages,
            NfcClient.InitializationCallback callback
    ) {
        ManagedNfcOperationDialog dialog = prepareInitializationDialog(
                messages,
                callback
        );
        if (dialog == null) {
            return;
        }
        client.startInitialize(
                message,
                marker,
                configuration,
                new ManagedInitializationCallback(dialog, callback)
        );
    }

    private ManagedNfcOperationDialog prepareDialog(
            NfcPresentationMessages.Write messages,
            NfcClient.WriteCallback callback
    ) {
        NfcError preparationError = preparationError();
        if (preparationError != null) {
            callback.onFailure(preparationError);
            return null;
        }
        return presentDialog(messages, client::cancelWrite, callback::onFailure);
    }

    private ManagedNfcOperationDialog prepareInitializationDialog(
            NfcPresentationMessages.Write messages,
            NfcClient.InitializationCallback callback
    ) {
        NfcError preparationError = preparationError();
        if (preparationError != null) {
            callback.onFailure(preparationError);
            return null;
        }
        return presentDialog(messages, client::cancelWrite, callback::onFailure);
    }

    private NfcError preparationError() {
        if (closed) {
            return new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "NfcWriteController has already been closed",
                    false
            );
        }
        if (client.isWriting()) {
            return new NfcError(
                    NfcErrorCode.WRITE_BUSY,
                    "Another NFC write operation is already active",
                    true
            );
        }
        return null;
    }

    private ManagedNfcOperationDialog presentDialog(
            NfcPresentationMessages.Write messages,
            Runnable cancellationAction,
            FailureCallback failureCallback
    ) {
        dismissDialog();
        Activity activity = activityRef.get();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            failureCallback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "The host Activity is not available",
                    false
            ));
            return null;
        }
        ManagedNfcOperationDialog dialog = new ManagedNfcOperationDialog(
                activity,
                ManagedNfcOperationDialog.Operation.WRITE,
                NfcPresentationMessages.resolveWrite(activity, messages),
                cancellationAction,
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
            failureCallback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "Unable to present the Android NFC write panel",
                    true,
                    error
            ));
            return null;
        }
        if (!dialog.isShowing()) {
            activeDialog = null;
            failureCallback.onFailure(new NfcError(
                    NfcErrorCode.INTERNAL_ERROR,
                    "The host Activity became unavailable before presentation",
                    true
            ));
            return null;
        }
        return dialog;
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

    private interface FailureCallback {
        void onFailure(NfcError error);
    }

    private static final class ManagedCallback
            implements NfcClient.WriteCallback {
        private final ManagedNfcOperationDialog dialog;
        private final NfcClient.WriteCallback callback;

        private ManagedCallback(
                ManagedNfcOperationDialog dialog,
                NfcClient.WriteCallback callback
        ) {
            this.dialog = dialog;
            this.callback = callback;
        }

        @Override
        public void onSuccess(NfcWriteResult result) {
            try {
                dialog.showSuccess();
            } finally {
                callback.onSuccess(result);
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
        public void onStateChanged(boolean writing) {
            callback.onStateChanged(writing);
        }
    }

    private static final class ManagedInitializationCallback
            implements NfcClient.InitializationCallback {
        private final ManagedNfcOperationDialog dialog;
        private final NfcClient.InitializationCallback callback;

        private ManagedInitializationCallback(
                ManagedNfcOperationDialog dialog,
                NfcClient.InitializationCallback callback
        ) {
            this.dialog = dialog;
            this.callback = callback;
        }

        @Override
        public void onSuccess(NfcInitializationResult result) {
            try {
                dialog.showSuccess();
            } finally {
                callback.onSuccess(result);
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
        public void onStateChanged(boolean writing) {
            callback.onStateChanged(writing);
        }
    }
}
