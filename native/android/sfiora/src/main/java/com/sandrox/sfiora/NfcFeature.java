package com.sandrox.sfiora;

/** Stable Android NFC features exposed by Sfiora. */
public enum NfcFeature {
    DISCOVER("discover"),
    NDEF("ndef"),
    NDEF_WRITE("ndefWrite"),
    NDEF_INITIALIZE("ndefInitialize"),
    READ_ONLY_MIFARE_ULTRALIGHT_PROBE("readOnlyMifareUltralightProbe"),
    READ_ONLY_TYPE_2_PROBE("readOnlyType2Probe"),
    READ_ONLY_MIFARE_CLASSIC_DEFAULT_KEY_PROBE(
            "readOnlyMifareClassicDefaultKeyProbe"
    );

    private final String value;

    NfcFeature(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
