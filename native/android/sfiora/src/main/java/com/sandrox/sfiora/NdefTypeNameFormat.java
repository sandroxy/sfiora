package com.sandrox.sfiora;

/**
 * Type Name Format values valid for a complete, non-chunked NDEF record.
 */
public enum NdefTypeNameFormat {
    EMPTY(0x00),
    WELL_KNOWN(0x01),
    MIME_MEDIA(0x02),
    ABSOLUTE_URI(0x03),
    EXTERNAL_TYPE(0x04),
    UNKNOWN(0x05);

    private final int value;

    NdefTypeNameFormat(int value) {
        this.value = value;
    }

    /**
     * Returns the NFC Forum TNF numeric value.
     */
    public int getValue() {
        return value;
    }
}
