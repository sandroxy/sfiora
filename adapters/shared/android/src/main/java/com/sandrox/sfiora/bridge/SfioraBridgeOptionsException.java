package com.sandrox.sfiora.bridge;

public final class SfioraBridgeOptionsException extends Exception {
    private static final long serialVersionUID = 1L;

    public SfioraBridgeOptionsException(String message) {
        super(message == null ? "Invalid NFC scan options" : message);
    }
}
