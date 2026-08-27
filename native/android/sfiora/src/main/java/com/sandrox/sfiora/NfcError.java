package com.sandrox.sfiora;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** An immutable NFC operation failure suitable for bridge conversion. */
public final class NfcError {
    private final NfcErrorCode code;
    private final String message;
    private final boolean recoverable;
    private final Throwable cause;

    public NfcError(
            NfcErrorCode code,
            String message,
            boolean recoverable
    ) {
        this(code, message, recoverable, null);
    }

    public NfcError(
            NfcErrorCode code,
            String message,
            boolean recoverable,
            Throwable cause
    ) {
        this.code = Objects.requireNonNull(code, "code is required");
        this.message = Objects.requireNonNull(message, "message is required");
        this.recoverable = recoverable;
        this.cause = cause;
    }

    public NfcErrorCode getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }

    public boolean isRecoverable() {
        return recoverable;
    }

    public Throwable getCause() {
        return cause;
    }

    /** Returns a stable value suitable for JS bridge conversion. */
    public Map<String, Object> toMap() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("code", code.getValue());
        result.put("message", message);
        result.put("recoverable", recoverable);
        if (cause != null) {
            Map<String, Object> nativeError = new LinkedHashMap<>();
            nativeError.put("type", cause.getClass().getSimpleName());
            nativeError.put(
                    "message",
                    cause.getMessage() == null
                            ? "No native error message"
                            : cause.getMessage()
            );
            result.put("nativeError", Collections.unmodifiableMap(nativeError));
        }
        return Collections.unmodifiableMap(result);
    }
}
