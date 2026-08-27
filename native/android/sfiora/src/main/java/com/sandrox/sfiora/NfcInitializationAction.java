package com.sandrox.sfiora;

/** Outcome of preserving or initializing one marked NDEF message. */
public enum NfcInitializationAction {
    PRESERVED("preserved"),
    INITIALIZED("initialized");

    private final String value;

    NfcInitializationAction(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
