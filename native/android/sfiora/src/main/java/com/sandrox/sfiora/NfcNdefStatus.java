package com.sandrox.sfiora;

/** NDEF access information observed during one tag operation. */
public enum NfcNdefStatus {
    NOT_CHECKED("notChecked"),
    NOT_SUPPORTED("notSupported"),
    READ_ONLY("readOnly"),
    READ_WRITE("readWrite"),
    READ_ERROR("readError"),
    UNKNOWN("unknown");

    private final String value;

    NfcNdefStatus(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
