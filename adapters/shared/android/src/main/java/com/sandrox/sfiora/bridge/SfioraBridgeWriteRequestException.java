package com.sandrox.sfiora.bridge;

public final class SfioraBridgeWriteRequestException extends Exception {
    private static final long serialVersionUID = 1L;

    public SfioraBridgeWriteRequestException(String message) {
        super(message == null ? "Invalid NFC write request" : message);
    }

    public SfioraBridgeWriteRequestException(String message, Throwable cause) {
        super(message == null ? "Invalid NFC write request" : message, cause);
    }
}
