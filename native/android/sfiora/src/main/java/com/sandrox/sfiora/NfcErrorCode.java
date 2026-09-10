package com.sandrox.sfiora;

/** Stable failure codes shared by the native implementations. */
public enum NfcErrorCode {
    NFC_UNSUPPORTED,
    NFC_DISABLED,
    SCAN_BUSY,
    WRITE_BUSY,
    USER_CANCELLED,
    SCAN_TIMEOUT,
    WRITE_TIMEOUT,
    SESSION_CLOSE_TIMEOUT,
    TAG_LOST,
    UNSUPPORTED_TAG,
    READ_FAILED,
    TAG_READ_ONLY,
    NDEF_CAPACITY_EXCEEDED,
    WRITE_FAILED,
    WRITE_VERIFICATION_FAILED,
    INVALID_OPTIONS,
    INTERNAL_ERROR;

    public String getValue() {
        return name();
    }
}
