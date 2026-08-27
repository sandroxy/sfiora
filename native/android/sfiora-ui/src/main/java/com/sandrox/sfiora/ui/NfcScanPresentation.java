package com.sandrox.sfiora.ui;

/**
 * Determines whether Android presents plugin-owned scan UI for one scan.
 */
public enum NfcScanPresentation {
    MANAGED("managed"),
    NONE("none");

    private final String bridgeValue;

    NfcScanPresentation(String bridgeValue) {
        this.bridgeValue = bridgeValue;
    }

    public String getBridgeValue() {
        return bridgeValue;
    }

    public static NfcScanPresentation fromBridgeValue(String value) {
        if (value == null) {
            return MANAGED;
        }
        for (NfcScanPresentation presentation : values()) {
            if (presentation.bridgeValue.equals(value)) {
                return presentation;
            }
        }
        throw new IllegalArgumentException(
                "presentation must be either managed or none"
        );
    }
}
