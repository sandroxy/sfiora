package com.sandrox.sfiora;

final class NfcOperationException extends Exception {
    private static final long serialVersionUID = 1L;

    private final NfcErrorCode code;
    private final boolean recoverable;

    NfcOperationException(
            NfcErrorCode code,
            String message,
            boolean recoverable
    ) {
        super(message);
        this.code = code;
        this.recoverable = recoverable;
    }

    NfcOperationException(
            NfcErrorCode code,
            String message,
            boolean recoverable,
            Throwable cause
    ) {
        super(message, cause);
        this.code = code;
        this.recoverable = recoverable;
    }

    NfcError toPublicError() {
        return new NfcError(code, getMessage(), recoverable, getCause());
    }
}
