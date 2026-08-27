package com.sandrox.sfiora;

/** Platform-neutral NFC technology names reported in tag snapshots. */
public enum NfcTechnology {
    NFC_A("nfcA"),
    NFC_B("nfcB"),
    NFC_F("nfcF"),
    NFC_V("nfcV"),
    ISO_DEP("isoDep"),
    ISO_7816("iso7816"),
    ISO_15693("iso15693"),
    MIFARE("mifare"),
    MIFARE_CLASSIC("mifareClassic"),
    MIFARE_ULTRALIGHT("mifareUltralight"),
    MIFARE_PLUS("mifarePlus"),
    MIFARE_DESFIRE("mifareDesfire"),
    MIFARE_UNKNOWN("mifareUnknown"),
    NDEF("ndef"),
    NDEF_FORMATABLE("ndefFormatable"),
    NFC_BARCODE("nfcBarcode"),
    UNKNOWN("unknown");

    private final String value;

    NfcTechnology(String value) {
        this.value = value;
    }

    public String getValue() {
        return value;
    }
}
