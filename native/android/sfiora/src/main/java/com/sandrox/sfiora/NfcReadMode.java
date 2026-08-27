package com.sandrox.sfiora;

/** Determines how one foreground tag scan handles NDEF data. */
public enum NfcReadMode {
    /** Returns tag identity and reads NDEF when the tag exposes it. */
    AUTOMATIC("automatic"),

    /** Requires a tag that exposes a readable NDEF message. */
    NDEF("ndef"),

    /** Returns tag identity without querying NDEF. */
    DISCOVER("discover");

    private final String value;

    NfcReadMode(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
