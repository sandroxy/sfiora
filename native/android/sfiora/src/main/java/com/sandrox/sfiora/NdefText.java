package com.sandrox.sfiora;

import java.util.Objects;

/**
 * A successfully decoded NFC Forum Text record payload.
 */
public final class NdefText {
    private final String text;
    private final String languageCode;
    private final NdefTextEncoding encoding;

    NdefText(
            String text,
            String languageCode,
            NdefTextEncoding encoding
    ) {
        this.text = Objects.requireNonNull(text, "text is required");
        this.languageCode = Objects.requireNonNull(
                languageCode,
                "languageCode is required"
        );
        this.encoding = Objects.requireNonNull(
                encoding,
                "encoding is required"
        );
    }

    public String getText() {
        return text;
    }

    public String getLanguageCode() {
        return languageCode;
    }

    public NdefTextEncoding getEncoding() {
        return encoding;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NdefText)) {
            return false;
        }
        NdefText that = (NdefText) other;
        return text.equals(that.text)
                && languageCode.equals(that.languageCode)
                && encoding == that.encoding;
    }

    @Override
    public int hashCode() {
        return Objects.hash(text, languageCode, encoding);
    }
}
