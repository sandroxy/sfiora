package com.sandrox.sfiora;

import android.app.Activity;
import android.nfc.FormatException;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.TagLostException;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.IOException;
import java.lang.ref.WeakReference;
import java.util.Arrays;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;

/**
 * Executes one foreground NFC read or write operation at a time.
 *
 * <p>Callbacks are always delivered on the Android main thread. The host must
 * call {@link #stop()} before its activity leaves the foreground and
 * {@link #close()} when the client is no longer needed. Connection cleanup runs
 * off the main thread. If cleanup takes over five seconds, the pending result
 * is delivered while state remains busy; the next operation must wait for the
 * state callback to report idle.</p>
 */
public final class NfcClient implements AutoCloseable {
    private static final String LOG_TAG = "SfioraNfcClient";
    private static final long COMPLETION_GRACE_MILLIS = 5000;

    public interface ReadCallback {
        void onSuccess(NfcTagSnapshot tag);

        void onFailure(NfcError error);

        default void onStateChanged(boolean reading) {
        }
    }

    public interface WriteCallback {
        void onSuccess(NfcWriteResult result);

        void onFailure(NfcError error);

        default void onStateChanged(boolean writing) {
        }
    }

    public interface InitializationCallback {
        void onSuccess(NfcInitializationResult result);

        void onFailure(NfcError error);

        default void onStateChanged(boolean writing) {
        }
    }

    private enum OperationKind {
        READ,
        WRITE,
        INITIALIZE
    }

    private static final class ActiveOperation {
        private final long identifier;
        private final OperationKind kind;
        private final NfcOperationCoordinator.Lease lease;
        private final NfcReadConfiguration readConfiguration;
        private final NfcWriteConfiguration writeConfiguration;
        private final NdefMessage message;
        private final NdefExternalType marker;
        private final ReadCallback readCallback;
        private final WriteCallback writeCallback;
        private final InitializationCallback initializationCallback;

        private boolean tagClaimed;
        private boolean stateReported;
        private boolean writeCommandStarted;
        private boolean writeVerified;
        private Future<?> task;
        private AndroidNdefConnection connection;
        private Runnable timeout;
        private boolean finishing;
        private boolean ioRunning;
        private boolean finalCloseScheduled;
        private Completion completion;
        private Runnable completionDeadline;

        private ActiveOperation(
                long identifier,
                OperationKind kind,
                NfcOperationCoordinator.Lease lease,
                NfcReadConfiguration readConfiguration,
                NfcWriteConfiguration writeConfiguration,
                NdefMessage message,
                NdefExternalType marker,
                ReadCallback readCallback,
                WriteCallback writeCallback,
                InitializationCallback initializationCallback
        ) {
            this.identifier = identifier;
            this.kind = kind;
            this.lease = lease;
            this.readConfiguration = readConfiguration;
            this.writeConfiguration = writeConfiguration;
            this.message = message;
            this.marker = marker;
            this.readCallback = readCallback;
            this.writeCallback = writeCallback;
            this.initializationCallback = initializationCallback;
        }
    }

    private interface Completion {
        void deliver(ActiveOperation operation);
    }

    private static final int READER_FLAGS =
            NfcAdapter.FLAG_READER_NFC_A
                    | NfcAdapter.FLAG_READER_NFC_B
                    | NfcAdapter.FLAG_READER_NFC_F
                    | NfcAdapter.FLAG_READER_NFC_V
                    | NfcAdapter.FLAG_READER_NFC_BARCODE;

    private final WeakReference<Activity> activityReference;
    private final NfcAdapter adapter;
    private final Handler mainHandler;
    private final ExecutorService worker;
    private final ExecutorService closer;
    private final Object stateLock = new Object();

    private ActiveOperation activeOperation;
    private long operationSequence;
    private boolean closed;

    public NfcClient(Activity activity) {
        Activity requiredActivity = Objects.requireNonNull(
                activity,
                "activity is required"
        );
        activityReference = new WeakReference<>(requiredActivity);
        adapter = NfcAdapter.getDefaultAdapter(
                requiredActivity.getApplicationContext()
        );
        mainHandler = new Handler(Looper.getMainLooper());
        worker = Executors.newSingleThreadExecutor(runnable -> {
            Thread thread = new Thread(runnable, "sfiora-nfc-io");
            thread.setDaemon(true);
            return thread;
        });
        closer = Executors.newSingleThreadExecutor(runnable -> {
            Thread thread = new Thread(runnable, "sfiora-nfc-close");
            thread.setDaemon(true);
            return thread;
        });
    }

    public NfcCapabilities getCapabilities() {
        return new NfcCapabilities(
                adapter != null,
                adapter != null && adapter.isEnabled()
        );
    }

    public boolean isReading() {
        synchronized (stateLock) {
            return activeOperation != null
                    && activeOperation.kind == OperationKind.READ;
        }
    }

    public boolean isWriting() {
        synchronized (stateLock) {
            return activeOperation != null
                    && activeOperation.kind != OperationKind.READ;
        }
    }

    public void startRead(
            NfcReadConfiguration configuration,
            ReadCallback callback
    ) {
        Objects.requireNonNull(configuration, "configuration is required");
        Objects.requireNonNull(callback, "callback is required");
        ActiveOperation operation = beginOperation(
                OperationKind.READ,
                configuration,
                null,
                null,
                null,
                callback,
                null,
                null
        );
        if (operation != null) {
            runOnMain(() -> enableReaderMode(operation));
        }
    }

    public void startWrite(
            NdefMessage message,
            NfcWriteConfiguration configuration,
            WriteCallback callback
    ) {
        Objects.requireNonNull(message, "message is required");
        Objects.requireNonNull(configuration, "configuration is required");
        Objects.requireNonNull(callback, "callback is required");
        ActiveOperation operation = beginOperation(
                OperationKind.WRITE,
                null,
                configuration,
                message,
                null,
                null,
                callback,
                null
        );
        if (operation != null) {
            runOnMain(() -> enableReaderMode(operation));
        }
    }

    public void startInitialize(
            NdefMessage message,
            NdefExternalType marker,
            NfcWriteConfiguration configuration,
            InitializationCallback callback
    ) {
        Objects.requireNonNull(message, "message is required");
        Objects.requireNonNull(marker, "marker is required");
        Objects.requireNonNull(configuration, "configuration is required");
        Objects.requireNonNull(callback, "callback is required");
        NdefWritePolicy.validateInitializationMessage(message, marker);
        ActiveOperation operation = beginOperation(
                OperationKind.INITIALIZE,
                null,
                configuration,
                message,
                marker,
                null,
                null,
                callback
        );
        if (operation != null) {
            runOnMain(() -> enableReaderMode(operation));
        }
    }

    public void cancelRead() {
        runOnMain(() -> cancel(OperationKind.READ));
    }

    public void cancelWrite() {
        runOnMain(() -> {
            ActiveOperation operation;
            synchronized (stateLock) {
                operation = activeOperation;
                if (operation == null || operation.kind == OperationKind.READ) {
                    return;
                }
            }
            cancelOperation(operation);
        });
    }

    /** Stops the active operation without delivering a terminal callback. */
    public void stop() {
        runOnMain(() -> {
            ActiveOperation operation;
            synchronized (stateLock) {
                operation = activeOperation;
            }
            if (operation != null) {
                operation.completion = null;
                completeOnMain(operation.identifier, null);
            }
        });
    }

    @Override
    public void close() {
        ActiveOperation operation;
        synchronized (stateLock) {
            if (closed) {
                return;
            }
            closed = true;
            operation = activeOperation;
        }
        runOnMain(() -> {
            if (operation != null) {
                completeOnMain(operation.identifier, null);
            } else {
                closer.shutdown();
            }
            worker.shutdownNow();
        });
    }

    private ActiveOperation beginOperation(
            OperationKind kind,
            NfcReadConfiguration readConfiguration,
            NfcWriteConfiguration writeConfiguration,
            NdefMessage message,
            NdefExternalType marker,
            ReadCallback readCallback,
            WriteCallback writeCallback,
            InitializationCallback initializationCallback
    ) {
        NfcError immediateError;
        ActiveOperation operation = null;
        synchronized (stateLock) {
            if (closed) {
                immediateError = new NfcError(
                        NfcErrorCode.INTERNAL_ERROR,
                        "The NFC client is closed",
                        false
                );
            } else if (adapter == null) {
                immediateError = new NfcError(
                        NfcErrorCode.NFC_UNSUPPORTED,
                        "This device does not support NFC",
                        false
                );
            } else if (!adapter.isEnabled()) {
                immediateError = new NfcError(
                        NfcErrorCode.NFC_DISABLED,
                        "NFC is disabled on this device",
                        true
                );
            } else if (activeOperation != null) {
                immediateError = busyError(kind);
            } else {
                NfcOperationCoordinator.Kind leaseKind =
                        kind == OperationKind.READ
                                ? NfcOperationCoordinator.Kind.READ
                                : NfcOperationCoordinator.Kind.WRITE;
                NfcOperationCoordinator.Lease lease =
                        NfcOperationCoordinator.tryAcquire(leaseKind);
                if (lease == null) {
                    immediateError = busyError(kind);
                } else {
                    operationSequence++;
                    operation = new ActiveOperation(
                            operationSequence,
                            kind,
                            lease,
                            readConfiguration,
                            writeConfiguration,
                            message,
                            marker,
                            readCallback,
                            writeCallback,
                            initializationCallback
                    );
                    activeOperation = operation;
                    immediateError = null;
                }
            }
        }

        if (immediateError != null) {
            deliverFailure(
                    kind,
                    readCallback,
                    writeCallback,
                    initializationCallback,
                    immediateError
            );
        }
        return operation;
    }

    private void enableReaderMode(ActiveOperation operation) {
        if (!isActive(operation.identifier)) {
            return;
        }
        Activity activity = activityReference.get();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            NfcErrorCode.INTERNAL_ERROR,
                            "The host activity is unavailable",
                            false
                    )
            );
            return;
        }

        Bundle extras = new Bundle();
        extras.putInt(
                NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY,
                presenceCheckDelayMillis(operation)
        );
        try {
            adapter.enableReaderMode(
                    activity,
                    tag -> onTagDiscovered(operation.identifier, tag),
                    READER_FLAGS,
                    extras
            );
            scheduleTimeout(operation);
            synchronized (stateLock) {
                if (activeOperation != operation) {
                    return;
                }
                operation.stateReported = true;
            }
            notifyStateChanged(operation, true);
        } catch (RuntimeException error) {
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            NfcErrorCode.INTERNAL_ERROR,
                            "Android could not enable NFC reader mode",
                            true,
                            error
                    )
            );
        }
    }

    private void scheduleTimeout(ActiveOperation operation) {
        Runnable timeout = () -> {
            ActiveOperation current = active(operation.identifier);
            if (current == null) {
                return;
            }
            NfcErrorCode code = current.kind == OperationKind.READ
                    ? NfcErrorCode.SCAN_TIMEOUT
                    : NfcErrorCode.WRITE_TIMEOUT;
            String message = current.kind == OperationKind.READ
                    ? "The NFC scan did not complete before the configured timeout"
                    : uncertainWriteMessage(
                            current,
                            "The NFC write did not complete before the configured timeout"
                    );
            completeWithFailure(
                    current.identifier,
                    new NfcError(code, message, true)
            );
        };
        synchronized (stateLock) {
            if (activeOperation != operation) {
                return;
            }
            operation.timeout = timeout;
        }
        mainHandler.postDelayed(timeout, timeoutMillis(operation));
    }

    private void onTagDiscovered(long identifier, Tag tag) {
        ActiveOperation operation;
        synchronized (stateLock) {
            operation = activeOperation;
            if (operation == null
                    || operation.identifier != identifier
                    || operation.finishing
                    || operation.tagClaimed) {
                return;
            }
            operation.tagClaimed = true;
            try {
                operation.task = worker.submit(() -> perform(operation, tag));
            } catch (RejectedExecutionException error) {
                runOnMain(() -> completeWithFailure(
                        identifier,
                        new NfcError(
                                NfcErrorCode.INTERNAL_ERROR,
                                "The NFC I/O executor is unavailable",
                                false,
                                error
                        )
                ));
            }
        }
    }

    private void perform(ActiveOperation operation, Tag tag) {
        synchronized (stateLock) {
            // Future.cancel() alone does not prove that a task has stopped.
            if (activeOperation != operation || operation.finishing) {
                return;
            }
            operation.ioRunning = true;
        }
        try {
            switch (operation.kind) {
                case READ:
                    performRead(operation, tag);
                    break;
                case WRITE:
                case INITIALIZE:
                    performWrite(operation, tag);
                    break;
                default:
                    throw new IllegalStateException(
                            "Unhandled NFC operation kind: " + operation.kind
                    );
            }
        } catch (NfcOperationException error) {
            completeWithFailure(operation.identifier, error.toPublicError());
        } catch (TagLostException error) {
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            NfcErrorCode.TAG_LOST,
                            uncertainWriteMessage(
                                    operation,
                                    "The NFC tag left the reader field"
                            ),
                            true,
                            error
                    )
            );
        } catch (FormatException error) {
            NfcErrorCode code = operationFailureCode(operation);
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            code,
                            uncertainWriteMessage(
                                    operation,
                                    "The NFC tag returned malformed NDEF data"
                            ),
                            false,
                            error
                    )
            );
        } catch (IOException | SecurityException error) {
            NfcErrorCode code = operationFailureCode(operation);
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            code,
                            uncertainWriteMessage(
                                    operation,
                                    "The NFC tag operation could not be completed"
                            ),
                            true,
                            error
                    )
            );
        } catch (RuntimeException error) {
            completeWithFailure(
                    operation.identifier,
                    new NfcError(
                            NfcErrorCode.INTERNAL_ERROR,
                            uncertainWriteMessage(
                                    operation,
                                    "An unexpected NFC implementation error occurred"
                            ),
                            false,
                            error
                    )
            );
        } finally {
            synchronized (stateLock) {
                operation.ioRunning = false;
            }
            runOnMain(() -> finishCleanupWhenReady(operation));
        }
    }

    private void performRead(ActiveOperation operation, Tag tag)
            throws IOException, FormatException, NfcOperationException {
        if (tag == null) {
            throw new NfcOperationException(
                    NfcErrorCode.READ_FAILED,
                    "Android returned an empty NFC tag",
                    true
            );
        }
        if (operation.readConfiguration.getMode() == NfcReadMode.DISCOVER) {
            completeWithRead(
                    operation.identifier,
                    AndroidTagSnapshotFactory.create(
                            tag,
                            AndroidTagSnapshotFactory.NdefObservation.notChecked(),
                            operation.readConfiguration
                    )
            );
            return;
        }

        AndroidNdefConnection connection = AndroidNdefConnection.from(tag);
        if (connection == null) {
            if (operation.readConfiguration.getMode() == NfcReadMode.NDEF) {
                throw new NfcOperationException(
                        NfcErrorCode.UNSUPPORTED_TAG,
                        "The detected tag does not expose NDEF data",
                        true
                );
            }
            completeWithRead(
                    operation.identifier,
                    AndroidTagSnapshotFactory.create(
                            tag,
                            AndroidTagSnapshotFactory.NdefObservation.unsupported(),
                            operation.readConfiguration
                    )
            );
            return;
        }

        registerConnection(operation, connection);
        AndroidTagSnapshotFactory.NdefObservation observation;
        NfcNdefStatus accessStatus = null;
        Integer capacityBytes = null;
        Boolean writable = null;
        Boolean canMakeReadOnly = null;
        String type = null;
        try {
            connection.connect();
            writable = connection.isWritable();
            canMakeReadOnly = connection.canMakeReadOnly();
            capacityBytes = connection.getCapacityBytes();
            type = connection.getType();
            accessStatus = writable
                    ? NfcNdefStatus.READ_WRITE
                    : NfcNdefStatus.READ_ONLY;
            AndroidNdefConnection.ReadResult readResult =
                    connection.read();
            String warning = readResult.getConversionError() == null
                    ? null
                    : "The raw NDEF message was preserved, but it could not "
                    + "be represented by Sfiora's typed NDEF model";
            observation = AndroidTagSnapshotFactory.NdefObservation.message(
                    accessStatus,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    readResult.getPlatformMessage(),
                    readResult.getMessage(),
                    warning
            );
        } catch (TagLostException error) {
            if (operation.readConfiguration.getMode() == NfcReadMode.NDEF) {
                throw error;
            }
            observation = AndroidTagSnapshotFactory.NdefObservation.readError(
                    accessStatus,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    error,
                    "NDEF tag lost before its message could be read"
            );
        } catch (IOException | FormatException error) {
            if (operation.readConfiguration.getMode() == NfcReadMode.NDEF) {
                throw error;
            }
            observation = AndroidTagSnapshotFactory.NdefObservation.readError(
                    accessStatus,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    error,
                    "NDEF metadata was found but the message could not be read"
            );
        } catch (RuntimeException error) {
            if (operation.readConfiguration.getMode() == NfcReadMode.NDEF) {
                throw new NfcOperationException(
                        NfcErrorCode.READ_FAILED,
                        "Unable to read the NDEF message",
                        true,
                        error
                );
            }
            observation = AndroidTagSnapshotFactory.NdefObservation.readError(
                    accessStatus,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    error,
                    "NDEF metadata was found but the message could not be read"
            );
        }
        if (operation.readConfiguration.isDeepReadEnabled()) {
            // Android permits only one connected TagTechnology per tag. Finish
            // the NDEF phase on this worker before the snapshot's memory probes.
            closeNdefBeforeProbe(operation, connection);
        }
        completeWithRead(
                operation.identifier,
                AndroidTagSnapshotFactory.create(
                        tag,
                        observation,
                        operation.readConfiguration
                )
        );
    }

    private void performWrite(ActiveOperation operation, Tag tag)
            throws IOException, FormatException, NfcOperationException {
        if (tag == null) {
            throw new NfcOperationException(
                    operation.kind == OperationKind.INITIALIZE
                            ? NfcErrorCode.READ_FAILED
                            : NfcErrorCode.WRITE_FAILED,
                    "Android returned an empty NFC tag",
                    true
            );
        }
        AndroidNdefConnection connection = AndroidNdefConnection.from(tag);
        if (connection == null) {
            throw new NfcOperationException(
                    NfcErrorCode.UNSUPPORTED_TAG,
                    "The detected tag is not formatted for NDEF",
                    true
            );
        }

        registerConnection(operation, connection);
        connection.connect();
        if (operation.kind == OperationKind.INITIALIZE) {
            AndroidNdefConnection.ReadResult current =
                    connection.read();
            if (containsMarker(current, operation.marker)) {
                NfcNdefStatus status = connection.isWritable()
                        ? NfcNdefStatus.READ_WRITE
                        : NfcNdefStatus.READ_ONLY;
                NfcTagSnapshot snapshot = snapshot(
                        tag,
                        connection,
                        status,
                        current
                );
                completeWithInitialization(
                        operation.identifier,
                        NfcInitializationResult.preserved(
                                operation.marker,
                                snapshot,
                                System.currentTimeMillis()
                        )
                );
                return;
            }
        }

        NdefWritePolicy.validateWritable(
                connection.isWritable(),
                connection.getCapacityBytes(),
                operation.message
        );
        markWriteCommandStarted(operation);
        connection.write(operation.message);

        AndroidNdefConnection.ReadResult verified;
        try {
            verified = connection.read();
        } catch (IOException | FormatException error) {
            throw new NfcOperationException(
                    NfcErrorCode.WRITE_VERIFICATION_FAILED,
                    "The tag was written but could not be read back for verification",
                    true,
                error
            );
        }
        if (verified.getConversionError() != null) {
            throw new NfcOperationException(
                    NfcErrorCode.WRITE_VERIFICATION_FAILED,
                    "The tag was written, but its NDEF message could not "
                            + "be represented for verification",
                    true,
                    verified.getConversionError()
            );
        }
        NdefWritePolicy.verify(operation.message, verified.getMessage());
        markWriteVerified(operation);
        NfcNdefStatus status = connection.isWritable()
                ? NfcNdefStatus.READ_WRITE
                : NfcNdefStatus.READ_ONLY;
        NfcTagSnapshot snapshot = snapshot(
                tag,
                connection,
                status,
                verified
        );
        long completedAt = System.currentTimeMillis();
        if (operation.kind == OperationKind.INITIALIZE) {
            completeWithInitialization(
                    operation.identifier,
                    NfcInitializationResult.initialized(
                            operation.marker,
                            snapshot,
                            operation.message,
                            completedAt
                    )
            );
        } else {
            completeWithWrite(
                    operation.identifier,
                    new NfcWriteResult(
                            snapshot,
                            operation.message,
                            completedAt
                    )
            );
        }
    }

    private void registerConnection(
            ActiveOperation operation,
            AndroidNdefConnection connection
    ) throws IOException {
        synchronized (stateLock) {
            if (activeOperation != operation || operation.finishing) {
                // Not connected yet; cancellation owns any registered connection.
                throw new IOException("The NFC operation is no longer active");
            }
            operation.connection = connection;
        }
    }

    private void closeNdefBeforeProbe(
            ActiveOperation operation,
            AndroidNdefConnection connection
    ) throws IOException {
        // A failed close must not be followed by another technology's connect.
        // Keep this connection registered while close blocks, so cancellation
        // can still interrupt it from the independent closer.
        connection.close();
        synchronized (stateLock) {
            if (activeOperation != operation || operation.finishing) {
                // Cancellation may already have queued a close of this object.
                // Retain it for final cleanup and never start another technology.
                throw new IOException("The NFC operation ended during technology switching");
            }
            // With no cancellation in progress, no queued closer can still own
            // this connection. Do not close an old NDEF object during a probe.
            operation.connection = null;
        }
    }

    private static void closeConnection(AndroidNdefConnection connection) {
        if (connection == null) {
            return;
        }
        try {
            connection.close();
        } catch (IOException | RuntimeException error) {
            // A stale Android tag cookie can throw SecurityException from close.
            Log.w(LOG_TAG, "NFC connection cleanup failed", error);
        }
    }

    private void markWriteCommandStarted(ActiveOperation operation)
            throws NfcOperationException {
        synchronized (stateLock) {
            if (activeOperation != operation || operation.finishing) {
                throw new NfcOperationException(
                        NfcErrorCode.USER_CANCELLED,
                        "The NFC write was cancelled",
                        true
                );
            }
            operation.writeCommandStarted = true;
        }
    }

    private void markWriteVerified(ActiveOperation operation) {
        synchronized (stateLock) {
            if (activeOperation == operation) {
                operation.writeVerified = true;
            }
        }
    }

    private static NfcTagSnapshot snapshot(
            Tag tag,
            AndroidNdefConnection connection,
            NfcNdefStatus status,
            AndroidNdefConnection.ReadResult readResult
    ) {
        String warning = readResult.getConversionError() == null
                ? null
                : "The raw NDEF message was preserved, but it could not be "
                + "represented by Sfiora's typed NDEF model";
        return AndroidTagSnapshotFactory.create(
                tag,
                AndroidTagSnapshotFactory.NdefObservation.message(
                        status,
                        connection.getCapacityBytes(),
                        connection.isWritable(),
                        connection.canMakeReadOnly(),
                        connection.getType(),
                        readResult.getPlatformMessage(),
                        readResult.getMessage(),
                        warning
                ),
                null
        );
    }

    private void completeWithRead(long identifier, NfcTagSnapshot tag) {
        complete(identifier, operation -> operation.readCallback.onSuccess(tag));
    }

    private void completeWithWrite(long identifier, NfcWriteResult result) {
        complete(identifier, operation -> operation.writeCallback.onSuccess(result));
    }

    private void completeWithInitialization(
            long identifier,
            NfcInitializationResult result
    ) {
        complete(
                identifier,
                operation -> operation.initializationCallback.onSuccess(result)
        );
    }

    private void completeWithFailure(long identifier, NfcError error) {
        complete(identifier, operation -> {
            NfcError deliveredError;
            synchronized (stateLock) {
                String message = uncertainWriteMessage(operation, error.getMessage());
                deliveredError = message.equals(error.getMessage()) ? error : new NfcError(
                        error.getCode(), message, error.isRecoverable(), error.getCause());
            }
            switch (operation.kind) {
                case READ:
                    operation.readCallback.onFailure(deliveredError);
                    break;
                case WRITE:
                    operation.writeCallback.onFailure(deliveredError);
                    break;
                case INITIALIZE:
                    operation.initializationCallback.onFailure(deliveredError);
                    break;
                default:
                    throw new IllegalStateException(
                            "Unhandled NFC operation kind: " + operation.kind
                    );
            }
        });
    }

    private void complete(long identifier, Completion completion) {
        runOnMain(() -> completeOnMain(identifier, completion));
    }

    private void completeOnMain(long identifier, Completion completion) {
        ActiveOperation operation;
        synchronized (stateLock) {
            operation = activeOperation;
            if (operation == null || operation.identifier != identifier
                    || operation.finishing) {
                return;
            }
            operation.finishing = true;
            operation.completion = completion;
        }

        if (operation.timeout != null) {
            mainHandler.removeCallbacks(operation.timeout);
        }
        // Keep the lease until both I/O and final close have returned. A close on
        // a separate executor can interrupt a blocked Binder read/write call.
        cancelIo(operation);
        operation.completionDeadline = () -> deliverCompletion(operation);
        mainHandler.postDelayed(operation.completionDeadline, COMPLETION_GRACE_MILLIS);
        finishCleanupWhenReady(operation);
    }

    private void finishCleanupWhenReady(ActiveOperation operation) {
        synchronized (stateLock) {
            if (activeOperation != operation || !operation.finishing
                    || operation.ioRunning || operation.finalCloseScheduled) {
                return;
            }
            operation.finalCloseScheduled = true;
        }
        // This final close is queued after any interruption close, and after the
        // worker exits. It covers cancellation racing with connection.connect().
        closer.execute(() -> {
            closeConnection(operation.connection);
            runOnMain(() -> finishCleanup(operation));
        });
    }

    private void finishCleanup(ActiveOperation operation) {
        synchronized (stateLock) {
            if (activeOperation != operation) {
                return;
            }
            activeOperation = null;
            operation.connection = null;
            if (closed) {
                closer.shutdown();
            }
        }
        mainHandler.removeCallbacks(operation.completionDeadline);
        Activity activity = activityReference.get();
        if (adapter != null && activity != null) {
            try {
                adapter.disableReaderMode(activity);
            } catch (RuntimeException ignored) {
                // The operation result takes precedence over teardown errors.
            }
        }
        NfcOperationCoordinator.release(operation.lease);
        if (operation.stateReported) {
            notifyStateChanged(operation, false);
        }
        deliverCompletion(operation);
    }

    private void deliverCompletion(ActiveOperation operation) {
        Completion completion = operation.completion;
        operation.completion = null;
        if (completion != null) {
            try {
                completion.deliver(operation);
            } catch (RuntimeException error) {
                Log.e(LOG_TAG, "NFC callback failed while delivering a result", error);
            }
        }
    }

    private void cancel(OperationKind kind) {
        ActiveOperation operation;
        synchronized (stateLock) {
            operation = activeOperation;
            if (operation == null || operation.kind != kind) {
                return;
            }
        }
        cancelOperation(operation);
    }

    private void cancelOperation(ActiveOperation operation) {
        completeWithFailure(
                operation.identifier,
                new NfcError(
                        NfcErrorCode.USER_CANCELLED,
                        uncertainWriteMessage(
                                operation,
                                operation.kind == OperationKind.READ
                                        ? "The NFC scan was cancelled"
                                        : "The NFC write was cancelled"
                        ),
                        true
                )
        );
    }

    private void cancelIo(ActiveOperation operation) {
        AndroidNdefConnection connection;
        Future<?> task;
        synchronized (stateLock) {
            connection = operation.ioRunning ? operation.connection : null;
            task = operation.task;
        }
        if (connection != null) {
            closer.execute(() -> closeConnection(connection));
        }
        if (task != null && !task.isDone()) {
            task.cancel(true);
        }
    }

    private ActiveOperation active(long identifier) {
        synchronized (stateLock) {
            return activeOperation != null
                    && activeOperation.identifier == identifier
                    && !activeOperation.finishing
                    ? activeOperation
                    : null;
        }
    }

    private boolean isActive(long identifier) {
        return active(identifier) != null;
    }

    private int presenceCheckDelayMillis(ActiveOperation operation) {
        return operation.kind == OperationKind.READ
                ? operation.readConfiguration.getPresenceCheckDelayMillis()
                : operation.writeConfiguration.getPresenceCheckDelayMillis();
    }

    private long timeoutMillis(ActiveOperation operation) {
        return operation.kind == OperationKind.READ
                ? operation.readConfiguration.getTimeoutMillis()
                : operation.writeConfiguration.getTimeoutMillis();
    }

    private static boolean containsMarker(
            AndroidNdefConnection.ReadResult readResult,
            NdefExternalType marker
    ) {
        android.nfc.NdefMessage platformMessage = readResult.getPlatformMessage();
        if (platformMessage == null) {
            return false;
        }
        byte[] expectedType = marker.encodedValueBytes();
        for (android.nfc.NdefRecord record : platformMessage.getRecords()) {
            if (record.getTnf() == android.nfc.NdefRecord.TNF_EXTERNAL_TYPE
                    && Arrays.equals(expectedType, record.getType())) {
                return true;
            }
        }
        return false;
    }

    private static NfcError busyError(OperationKind requestedKind) {
        boolean reading = requestedKind == OperationKind.READ;
        return new NfcError(
                reading ? NfcErrorCode.SCAN_BUSY : NfcErrorCode.WRITE_BUSY,
                "Another NFC read or write operation is already active",
                true
        );
    }

    private static NfcErrorCode operationFailureCode(
            ActiveOperation operation
    ) {
        if (operation.kind == OperationKind.READ
                || (operation.kind == OperationKind.INITIALIZE
                && !operation.writeCommandStarted)) {
            return NfcErrorCode.READ_FAILED;
        }
        return NfcErrorCode.WRITE_FAILED;
    }

    private static String uncertainWriteMessage(
            ActiveOperation operation,
            String baseMessage
    ) {
        if (operation.kind != OperationKind.READ
                && operation.writeCommandStarted
                && !operation.writeVerified
                && !baseMessage.contains("the tag may have changed because the write was not verified")) {
            return baseMessage
                    + "; the tag may have changed because the write was not verified";
        }
        return baseMessage;
    }

    private void deliverFailure(
            OperationKind kind,
            ReadCallback readCallback,
            WriteCallback writeCallback,
            InitializationCallback initializationCallback,
            NfcError error
    ) {
        runOnMain(() -> {
            try {
                switch (kind) {
                    case READ:
                        readCallback.onFailure(error);
                        break;
                    case WRITE:
                        writeCallback.onFailure(error);
                        break;
                    case INITIALIZE:
                        initializationCallback.onFailure(error);
                        break;
                    default:
                        throw new IllegalStateException(
                                "Unhandled NFC operation kind: " + kind
                        );
                }
            } catch (RuntimeException callbackError) {
                Log.e(LOG_TAG, "NFC callback failed while delivering an error", callbackError);
            }
        });
    }

    private static void notifyStateChanged(
            ActiveOperation operation,
            boolean active
    ) {
        try {
            switch (operation.kind) {
                case READ:
                    operation.readCallback.onStateChanged(active);
                    break;
                case WRITE:
                    operation.writeCallback.onStateChanged(active);
                    break;
                case INITIALIZE:
                    operation.initializationCallback.onStateChanged(active);
                    break;
                default:
                    throw new IllegalStateException(
                            "Unhandled NFC operation kind: " + operation.kind
                    );
            }
        } catch (RuntimeException error) {
            Log.e(LOG_TAG, "NFC callback failed while delivering state", error);
        }
    }

    private void runOnMain(Runnable action) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run();
        } else {
            mainHandler.post(action);
        }
    }
}
