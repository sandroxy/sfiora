package com.sandrox.sfiora;

/**
 * Text encodings defined by the NFC Forum Text Record Type Definition.
 */
public enum NdefTextEncoding {
    UTF_8("UTF-8"),
    UTF_16("UTF-16");

    private final String standardName;

    NdefTextEncoding(String standardName) {
        this.standardName = standardName;
    }

    public String getStandardName() {
        return standardName;
    }
}
