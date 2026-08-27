package com.sandrox.sfiora;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Locale;
import java.util.Objects;

/** A canonical NFC Forum External Type used to identify an NDEF record. */
public final class NdefExternalType {
    private final String domain;
    private final String type;
    private final String value;
    private final byte[] encodedValue;

    public NdefExternalType(String domain, String type) {
        this.domain = Objects.requireNonNull(domain, "domain is required");
        this.type = Objects.requireNonNull(type, "type is required");
        value = domain + ":" + type;
        if (!value.equals(value.toLowerCase(Locale.ROOT))
                || !NdefRecord.isValidExternalType(value)) {
            throw new IllegalArgumentException(
                    "NDEF external type must be a lowercase domain:type value"
            );
        }
        encodedValue = value.getBytes(StandardCharsets.US_ASCII);
    }

    public String getDomain() {
        return domain;
    }

    public String getType() {
        return type;
    }

    public String getValue() {
        return value;
    }

    public boolean matches(NdefRecord record) {
        return record != null
                && record.getTypeNameFormat()
                == NdefTypeNameFormat.EXTERNAL_TYPE
                && Arrays.equals(encodedValue, record.typeBytes());
    }

    byte[] encodedValueBytes() {
        return encodedValue.clone();
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NdefExternalType)) {
            return false;
        }
        NdefExternalType that = (NdefExternalType) other;
        return value.equals(that.value);
    }

    @Override
    public int hashCode() {
        return value.hashCode();
    }
}
